#!/usr/bin/env bash
# Daily dotfiles auto-update — fast-forward pull only.
#
# Safe by construction: never clobbers local work (skips a dirty tree), never
# merges/rebases (fast-forward only), never pushes. Scheduled once a day by
# this module's install scripts: launchd on macOS, a systemd user timer on
# Linux. Logs to $XDG_STATE_HOME/dotfiles/autoupdate.log.
set -euo pipefail

# Resolve the repo root from this script's own location (robust to env-less
# launchd/systemd invocation), overridable via $DOTFILES.
DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG="$LOG_DIR/autoupdate.log"
mkdir -p "$LOG_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG"; }

cd "$DOTFILES" 2>/dev/null || {
  log "ERROR: DOTFILES=$DOTFILES not found"
  exit 0
}

# Never touch a tree with local changes — a human owns those.
if [ -n "$(git status --porcelain)" ]; then
  log "skip: working tree has local changes"
  exit 0
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  log "skip: $branch has no upstream"
  exit 0
fi

if ! git fetch --quiet --prune origin 2>>"$LOG"; then
  log "skip: fetch failed (offline?)"
  exit 0
fi

local_rev="$(git rev-parse @)"
remote_rev="$(git rev-parse '@{u}')"
if [ "$local_rev" = "$remote_rev" ]; then
  log "ok: up to date ($branch @ ${local_rev:0:8})"
  exit 0
fi

# Fast-forward only — a diverged branch needs a human, never an auto-merge.
if git merge --ff-only --quiet '@{u}' 2>>"$LOG"; then
  log "updated: $branch ${local_rev:0:8} -> $(git rev-parse --short @)"
else
  log "skip: $branch diverged from upstream — needs a manual pull"
fi
