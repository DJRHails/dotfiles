#!/usr/bin/env bash
# Behavior suite for modules/dotfiles-autoupdate/update.sh.
# Self-contained: `bash tests/dotfiles-autoupdate.test.sh`. Exits non-zero on failure.
#
# Covers the stash-and-reapply path, which exists because apps write into
# tracked config through their symlinks: a local edit must survive the daily
# fast-forward, and one that conflicts must be parked in a stash rather than
# popped into the working tree as conflict markers.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
update_sh="$repo_root/modules/dotfiles-autoupdate/update.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

git_quiet() { git -C "$clone" -c user.email=t@t -c user.name=t "$@" > /dev/null 2>&1; }

# The script prepends $HOME/.local/bin to PATH, so a fake HOME is the only way
# to put a stub ahead of a real glassine — and it keeps the suite from writing
# ~/.gitconfig.github-ssh into the developer's actual home. git identity has to
# be supplied because the stash the updater takes creates commit objects.
fake_home="$work/home"

# A bare origin plus a clone, so the script's fetch/merge run for real.
setup_repo() {
  rm -rf -- "$work/origin" "$work/clone" "$work/state" "$fake_home" "$work/glassine.calls"
  mkdir -p "$fake_home"
  printf '[user]\n\tname = t\n\temail = t@t\n' > "$fake_home/.gitconfig"
  git init --quiet --bare "$work/origin"
  git clone --quiet "$work/origin" "$work/clone" 2> /dev/null
  clone="$work/clone"
  printf 'default\n' > "$clone/settings.json"
  printf 'untouched\n' > "$clone/other.txt"
  git_quiet add -A
  git_quiet commit -m "initial"
  git_quiet push -u origin HEAD:main
  git_quiet branch --set-upstream-to=origin/main
}

# Land a new upstream commit, made in a throwaway clone so $clone stays behind.
push_upstream() {
  local file=$1 content=$2 up="$work/upstream"
  rm -rf -- "$up"
  git clone --quiet "$work/origin" "$up" 2> /dev/null
  printf '%s\n' "$content" > "$up/$file"
  git -C "$up" -c user.email=t@t -c user.name=t add -A > /dev/null
  git -C "$up" -c user.email=t@t -c user.name=t commit -m "upstream edit" > /dev/null
  git -C "$up" push --quiet origin HEAD:main
}

# Runs in a subshell via `log="$(run_update)"`, so the exit status goes to a
# file rather than a variable the caller could never see.
run_update() {
  DOTFILES="$clone" XDG_STATE_HOME="$work/state" HOME="$fake_home" \
    bash "$update_sh" > /dev/null 2>&1
  printf '%s\n' "$?" > "$work/status"
  cat "$work/state/dotfiles/autoupdate.log"
}

# A stand-in for glassine on PATH, faithful to the two parts of its contract the
# updater leans on: `init` rewrites still-encrypted worktree files in place, and
# reports how many on stdout. Real decryption needs sops, an age identity and a
# .sops.yaml — none of which belong in a behaviour test of the updater.
stub_glassine() {
  local mode=${1:-repair}
  mkdir -p "$fake_home/.local/bin"
  cat > "$fake_home/.local/bin/glassine" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$work/glassine.calls"
if [ "$mode" = fail ]; then
  echo 'glassine: no decryption identity found' >&2
  exit 1
fi
count=0
while IFS= read -r f; do
  grep -qF 'ENC[AES256_GCM' "$clone/\$f" 2> /dev/null || continue
  printf 'decrypted-plaintext\n' > "$clone/\$f"
  count=\$((count + 1))
done < <(git -C "$clone" ls-files)
[ "\$count" -eq 0 ] ||
  printf 'glassine: decrypted %d file(s) into the working tree\n' "\$count"
exit 0
STUB
  chmod +x "$fake_home/.local/bin/glassine"
}

# Mark the clone as a glassine repo without installing real filters: the updater
# gates on this config alone, and a real clean filter would need sops.
enable_glassine_filter() { git -C "$clone" config filter.glassine.clean 'glassine clean %f'; }

# --- a local edit that does not collide is carried over the update ----------
setup_repo
push_upstream other.txt "upstream-changed"
printf 'locally-picked-model\n' > "$clone/settings.json"
log="$(run_update)"

check "clean reapply: pulls" \
  "upstream-changed" "$(cat "$clone/other.txt")"
check "clean reapply: keeps the local edit" \
  "locally-picked-model" "$(cat "$clone/settings.json")"
check "clean reapply: nothing left in the stash" \
  "0" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "clean reapply: logged" \
  "1" "$(grep -c 'reapplied local changes' <<< "$log")"

# --- a local edit to the same lines is parked, never popped as markers ------
setup_repo
push_upstream settings.json "upstream-model"
printf 'locally-picked-model\n' > "$clone/settings.json"
log="$(run_update)"

check "conflict: still pulls" \
  "upstream-model" "$(cat "$clone/settings.json")"
# Count with `grep -c` on one file, never `grep -rc`: BSD grep prefixes the
# filename in recursive mode, so the comparison broke on macOS while the
# behaviour under test was fine.
check "conflict: no conflict markers in the tree" \
  "0" "$(grep -c '^<<<<<<<' "$clone/settings.json" | tr -d ' ')"
check "conflict: tree is clean" \
  "" "$(git -C "$clone" status --porcelain)"
check "conflict: local work kept in the stash" \
  "1" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "conflict: stash is recoverable" \
  "locally-picked-model" "$(git -C "$clone" stash show -p stash@'{0}' | grep '^+locally' | cut -c2-)"
check "conflict: logged with the recovery command" \
  "1" "$(grep -c 'CONFLICT with the update' <<< "$log")"

# --- a clean tree still fast-forwards, and takes no stash -------------------
setup_repo
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "clean tree: pulls" \
  "upstream-changed" "$(cat "$clone/other.txt")"
check "clean tree: no stash taken" \
  "0" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "clean tree: logged as updated" \
  "1" "$(grep -c 'updated: ' <<< "$log")"

# --- already up to date is a no-op ------------------------------------------
log="$(run_update)"
check "up to date: logged" "1" "$(grep -c 'ok: up to date' <<< "$log")"

# --- a diverged branch is never auto-merged ---------------------------------
setup_repo
push_upstream other.txt "upstream-changed"
printf 'local commit\n' > "$clone/local.txt"
git_quiet add -A
git_quiet commit -m "local divergence"
local_head="$(git -C "$clone" rev-parse HEAD)"
log="$(run_update)"

check "diverged: HEAD untouched" "$local_head" "$(git -C "$clone" rev-parse HEAD)"
check "diverged: logged" "1" "$(grep -c 'diverged from upstream' <<< "$log")"

# --- ciphertext stranded in the worktree is detected and repaired -----------
# A hand-resolved conflict (or a checkout with glassine off PATH) writes the raw
# sops envelope into the working tree while git still calls the tree clean, so
# nothing flags it. Two skills sat unreadable that way for a week.
setup_repo
stub_glassine
enable_glassine_filter
printf 'ENC[AES256_GCM,data:xx]\n' > "$clone/secret.md"
git_quiet add -A
git_quiet commit -m "encrypted-at-rest file"
git_quiet push origin HEAD:main
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "glassine repair: worktree is plaintext again" \
  "decrypted-plaintext" "$(cat "$clone/secret.md")"
check "glassine repair: names the repair in the log" \
  "1" "$(grep -c 'repaired unsmudged files: decrypted 1 file' <<< "$log")"
check "glassine repair: went through init" \
  "init" "$(cat "$work/glassine.calls")"

# --- a repo that has not opted into glassine is never touched ---------------
# Running `glassine init` against an unmanaged repo would bootstrap .sops.yaml
# and filters into it, so the config gate has to hold.
setup_repo
stub_glassine
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "no glassine filter: glassine is not invoked" \
  "never-called" "$(cat "$work/glassine.calls" 2> /dev/null || echo never-called)"
check "no glassine filter: still pulls" \
  "upstream-changed" "$(cat "$clone/other.txt")"

# --- a glassine that cannot decrypt is logged, never fatal ------------------
# No identity on this host is a warning: the update itself must still land, and
# the rest of the daily run must still happen.
setup_repo
stub_glassine fail
enable_glassine_filter
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "glassine failure: warned" \
  "1" "$(grep -c 'WARNING: glassine init failed' <<< "$log")"
check "glassine failure: the update still landed" \
  "upstream-changed" "$(cat "$clone/other.txt")"
check "glassine failure: no repair claimed" \
  "0" "$(grep -c 'repaired unsmudged files' <<< "$log")"

# --- a clean-tree update still runs the steps after the pull ----------------
# `update_dotfiles` ends on the stash branch, so an `&&` one-liner there made it
# return 1 whenever no stash was taken; `set -e` then killed the run before the
# pi refresh and the ssh-rewrite. Two fast-forwards on 2026-08-05 skipped them
# silently, so assert on a side effect of the last step, not just the exit code.
setup_repo
mkdir -p "$fake_home/.ssh"
printf 'Host github.com\n  User git\n' > "$fake_home/.ssh/config"
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "clean-tree update: exits 0" "0" "$(cat "$work/status")"
check "clean-tree update: no stash was taken" \
  "0" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "clean-tree update: later steps still ran" \
  "1" "$([ -f "$fake_home/.gitconfig.github-ssh" ] && echo 1 || echo 0)"

if ((fails)); then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
