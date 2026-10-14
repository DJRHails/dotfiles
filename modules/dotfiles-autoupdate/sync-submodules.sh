#!/usr/bin/env bash
# Move each submodule of a repo to the commit its superproject HEAD records —
# but only where nothing can be lost. Shared by the daily update.sh and the
# manual `dotfiles::update`.
#
# Why: a pin bump lands with the fast-forward, but the submodule's worktree
# stays at the old commit until someone runs `git submodule update`. Skills
# vendored as submodules are loaded live from the checkout, so a lagging
# worktree means a stale skill.
#
# A submodule is moved only when it is initialised, its HEAD is detached (a
# checked-out branch means someone is working there), and it has no modified or
# staged tracked files. Untracked files never block the move and are kept:
# `git checkout` leaves them alone (and refuses, logged, if the new commit
# would overwrite one). A missing pin is fetched inside the submodule; a fetch
# failure skips that submodule only. Never forces, never resets, never pushes.
#
# Usage: sync-submodules.sh <repo>. One line per move or skip goes to stdout;
# git's own errors go to stderr. Always exits 0 once <repo> is reachable.
set -euo pipefail

repo="${1:?usage: sync-submodules.sh <repo>}"
cd "$repo"

# Prints the reason a submodule must not be moved, or nothing when it is safe.
unsafe_reason() {
  local path=$1 branch
  if branch="$(git -C "$path" symbolic-ref --quiet --short HEAD)"; then
    printf 'on branch %s' "$branch"
  elif [ -n "$(git -C "$path" status --porcelain --untracked-files=no)" ]; then
    printf 'modified tracked files'
  fi
}

has_commit() { git -C "$1" cat-file -e "$2^{commit}" 2> /dev/null; }

# Fetch the pin if it is missing: branch tips first, then the bare commit id
# (a pin need not be any branch's tip).
ensure_commit() {
  local path=$1 want=$2
  has_commit "$path" "$want" && return 0
  git -C "$path" fetch --quiet origin < /dev/null || true
  has_commit "$path" "$want" && return 0
  git -C "$path" fetch --quiet origin "$want" < /dev/null || true
  has_commit "$path" "$want"
}

sync_one() {
  local path=$1 want have reason
  # Initialising is bootstrap's job: some submodules are deliberately absent.
  [ -e "$path/.git" ] || return 0
  want="$(git rev-parse --verify --quiet "HEAD:$path")" || return 0
  have="$(git -C "$path" rev-parse --verify --quiet HEAD)" || {
    echo "submodule $path: skip — HEAD unreadable"
    return 0
  }
  [ "$have" = "$want" ] && return 0

  reason="$(unsafe_reason "$path")"
  if [ -n "$reason" ]; then
    echo "submodule $path: skip — $reason (pin is ${want:0:8}, at ${have:0:8})"
    return 0
  fi
  if ! ensure_commit "$path" "$want"; then
    echo "submodule $path: skip — pin ${want:0:8} not available (fetch failed?)"
    return 0
  fi
  if git -C "$path" checkout --quiet --detach "$want" < /dev/null; then
    echo "submodule $path: ${have:0:8} -> ${want:0:8}"
  else
    echo "submodule $path: FAILED to check out ${want:0:8} (see errors above)"
  fi
}

[ -f .gitmodules ] || exit 0
# Collected first so a git call inside the loop cannot eat the list on stdin.
paths="$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' |
  cut -d' ' -f2-)" || exit 0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  sync_one "$path"
done <<< "$paths"
exit 0
