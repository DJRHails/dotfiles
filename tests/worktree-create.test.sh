#!/usr/bin/env bash
# Behavior suite for modules/agents/skills/worktree/scripts/worktree-create.sh.
# Self-contained: `bash tests/worktree-create.test.sh`. Exits non-zero on failure.
#
# The root checkout is shared by several live agent sessions, so creating a worktree must
# never modify it. The script used to `git stash push` the root's uncommitted edits so its
# clonefile fast path could copy a clean tree, then `stash pop` them on EXIT: other sessions
# saw their files revert mid-flight, and a pop that conflicted (or popped someone else's
# stash, or never ran) left their work in a dangling stash commit. These checks pin that the
# root is byte-identical before, during and after, the stash list is untouched, and the new
# worktree still holds exactly the committed tree plus the bootstrapped untracked files.
set -euo pipefail

unset "${!GIT_@}"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
create="$(cd "$script_dir/.." && pwd)/modules/agents/skills/worktree/scripts/worktree-create.sh"

# SKILL.md documents `bash worktree-create.sh`, and in a non-interactive shell on macOS that
# bash is the stock /bin/bash 3.2. The script needs a newer one and must find it by itself:
# it once died on `declare -A` half-way through, after its pre-scan. So run it under the
# oldest bash here; where every bash is new enough, the run still covers the plain path.
runner=bash
while IFS= read -r candidate; do
  if "$candidate" -c '((BASH_VERSINFO[0] < 4))' 2>/dev/null; then
    runner="$candidate"
    break
  fi
done < <(
  type -ap bash
  echo /bin/bash
)
printf 'running worktree-create.sh under %s: %s\n' "$runner" "$("$runner" --version | head -1)"

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf -- "$work"' EXIT

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# A snapshot of everything another session could see in the root checkout: the content of
# every file outside .git and .data, the index, and the stash list.
snapshot() {
  local main="$1"
  (
    cd "$main"
    find . \( -path ./.git -o -path ./.data \) -prune -o -type f -print0 |
      LC_ALL=C sort -z | xargs -0 shasum
    git ls-files --stage
    git stash list --format='%H %gs'
  ) | shasum | awk '{print $1}'
}

main="$work/main"
mkdir -p "$main/sub" "$main/node_modules/pkg"
git -C "$main" init -q -b main
git -C "$main" config user.name test
git -C "$main" config user.email test@example.com
printf 'node_modules/\n.env\n.data\n' >"$main/.gitignore"
printf 'committed a\n' >"$main/a.txt"
printf 'committed b\n' >"$main/sub/b.txt"
printf 'committed gone\n' >"$main/gone.txt"
git -C "$main" add -A
git -C "$main" commit -qm base

# Someone else's stash, already on the stack: a pop from the script must never reach it.
printf 'other session stash\n' >"$main/a.txt"
git -C "$main" stash push -qm "another session's stash"

# Live edits from other sessions, in every shape git distinguishes. The edit to a.txt keeps
# its size, so only a content check (not a size check) can tell it from the commit.
printf 'COMMITTED A\n' >"$main/a.txt"
printf 'staged b\n' >"$main/sub/b.txt"
git -C "$main" add sub/b.txt
rm "$main/gone.txt"
printf 'staged new\n' >"$main/new.txt"
git -C "$main" add new.txt
printf 'untracked\n' >"$main/scratch.txt"
printf 'SECRET=1\n' >"$main/.env"
printf 'module.exports = 1\n' >"$main/node_modules/pkg/index.js"

before="$(snapshot "$main")"

# Probe the root from inside the run: every checkout the script makes fires post-checkout,
# which records the root's snapshot at that moment. The stash used to sit across this window.
hooks="$work/hooks"
mkdir -p "$hooks"
cat >"$hooks/post-checkout" <<HOOK
#!/usr/bin/env bash
unset "\${!GIT_@}"
$(declare -f snapshot)
snapshot "$main" >>"$work/during.log"
HOOK
chmod +x "$hooks/post-checkout"
git -C "$main" config core.hooksPath "$hooks"

out="$(cd "$main" && "$runner" "$create" feature 2>&1)" || {
  printf 'FAIL worktree-create.sh exited non-zero:\n%s\n' "$out"
  exit 1
}
wt="$main/.data/worktrees/feature"

if [[ "$(uname)" == Darwin ]] && command -v cpow >/dev/null 2>&1; then
  check "dirty root still takes the clonefile fast path" "yes" \
    "$(grep -q 'clonefile fast path' <<<"$out" && ! grep -q 'falling back' <<<"$out" &&
      echo yes || echo no)"
fi

check "root is byte-identical after the run" "$before" "$(snapshot "$main")"
during_bad="$(grep -cvxF "$before" "$work/during.log" || true)"
check "root is byte-identical during the run" "0" "$during_bad"
check "post-checkout probe ran during the run" "yes" \
  "$([[ -s "$work/during.log" ]] && echo yes || echo no)"
check "stash list is unchanged" "another session's stash" \
  "$(git -C "$main" stash list --format='%gs' | sed 's/^On main: //')"

check "worktree is on the new branch" "feature" "$(git -C "$wt" branch --show-current)"
check "worktree has the committed a.txt" "committed a" "$(cat "$wt/a.txt")"
check "worktree has the committed sub/b.txt" "committed b" "$(cat "$wt/sub/b.txt")"
check "worktree has the file deleted in the root" "committed gone" "$(cat "$wt/gone.txt")"
check "worktree lacks the root's staged-only file" "absent" \
  "$([[ -e "$wt/new.txt" ]] && echo present || echo absent)"
check "worktree lacks the root's untracked scratch file" "absent" \
  "$([[ -e "$wt/scratch.txt" ]] && echo present || echo absent)"
check "worktree status is clean" "" "$(git -C "$wt" status --porcelain)"
check ".env is copied" "SECRET=1" "$(cat "$wt/.env")"
check "node_modules is copied" "module.exports = 1" "$(cat "$wt/node_modules/pkg/index.js")"

if ((fails > 0)); then
  printf '%d check(s) failed\n' "$fails"
  exit 1
fi
printf 'all checks passed\n'
