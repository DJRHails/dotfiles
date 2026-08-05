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

# A bare origin plus a clone, so the script's fetch/merge run for real.
setup_repo() {
  rm -rf -- "$work/origin" "$work/clone" "$work/state"
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

run_update() {
  DOTFILES="$clone" XDG_STATE_HOME="$work/state" bash "$update_sh" > /dev/null 2>&1
  cat "$work/state/dotfiles/autoupdate.log"
}

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

if ((fails)); then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
