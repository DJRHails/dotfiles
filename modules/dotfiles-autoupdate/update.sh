#!/usr/bin/env bash
# Daily auto-update — fast-forward pull of the dotfiles repo, then a refresh of
# pi's installed extension packages.
#
# Safe by construction: never clobbers local work (skips a dirty tree), never
# merges/rebases (fast-forward only), never pushes. Scheduled once a day by
# this module's install scripts: launchd on macOS, a systemd user timer on
# Linux. Logs to $XDG_STATE_HOME/dotfiles/autoupdate.log.
set -euo pipefail

# launchd/systemd/cron hand us a minimal PATH that omits ~/.local/bin and
# Homebrew, so tools git itself needs are missing: without `glassine` on PATH
# the repo's clean filter fails with 127, `git merge --ff-only` aborts, and the
# daily pull silently reported "diverged" for a week (2026-07-28..08-04).
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

# Resolve the repo root from this script's own location (robust to env-less
# launchd/systemd invocation), overridable via $DOTFILES.
DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
LOG="$LOG_DIR/autoupdate.log"
mkdir -p "$LOG_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG"; }

# Fast-forward the dotfiles repo. Returns non-zero only for "could not even
# start"; every ordinary skip is logged and returns 0 so the pi refresh below
# still runs (the common case is an already-up-to-date tree).
update_dotfiles() {
  cd "$DOTFILES" 2>/dev/null || {
    log "ERROR: DOTFILES=$DOTFILES not found"
    return 0
  }

  local branch local_rev
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    log "skip: $branch has no upstream"
    return 0
  fi

  # Superproject only — never let a submodule fetch failure block the daily pull.
  if ! git fetch --quiet --prune --no-recurse-submodules origin 2>>"$LOG"; then
    log "skip: fetch failed (offline?)"
    return 0
  fi

  local_rev="$(git rev-parse @)"
  if [ "$local_rev" = "$(git rev-parse '@{u}')" ]; then
    log "ok: up to date ($branch @ ${local_rev:0:8})"
    return 0
  fi

  # Local edits ride over the update on a stash. Apps write into tracked config
  # through their symlinks (Claude Code persists `/model`, pi persists
  # `defaultModel`), so "dirty" is the steady state here, and the old behaviour —
  # skip while dirty — parked the pull for 12 days on one host and 5 on another.
  # Untracked files are left in place: they don't block a fast-forward unless
  # upstream adds the same path, and that case should fail loudly below.
  local stashed=false
  if [ -n "$(git status --porcelain --untracked-files=no --ignore-submodules=all)" ]; then
    if git stash push --quiet --message "dotfiles-autoupdate $(date '+%Y-%m-%dT%H:%M:%S%z')" 2>>"$LOG"; then
      stashed=true
      log "stashed local changes before updating"
    else
      log 'skip: local changes present and the stash push failed'
      return 0
    fi
  fi

  # Fast-forward only — a diverged branch needs a human, never an auto-merge.
  # Submodules are left untouched (never checked out over possible in-submodule
  # WIP); run `git submodule update` by hand to follow a bumped pin.
  if git merge --ff-only --quiet '@{u}' 2>>"$LOG"; then
    log "updated: $branch ${local_rev:0:8} -> $(git rev-parse --short @)"
  elif git merge-base --is-ancestor @ '@{u}'; then
    log "ERROR: $branch is behind upstream but the fast-forward FAILED (see errors above)"
  else
    log "skip: $branch diverged from upstream — needs a manual pull"
  fi

  # An `&&` one-liner here would make the function return 1 whenever no stash
  # was taken, and `set -e` then kills the script before the steps below it: on
  # 2026-08-05 two clean-tree fast-forwards (13:13, 13:27) silently skipped the
  # pi package refresh entirely. Every early return above is a deliberate 0.
  if [ "$stashed" = true ]; then
    restore_stash
  fi
}

# Reapply the stash taken above — but only when it applies cleanly.
#
# `git stash pop` on a conflict leaves conflict MARKERS in tracked files and
# drops nothing, which is how a settings.json full of `<<<<<<< Updated upstream`
# reached a running agent and broke it (2026-08-04). So dry-run the patch first
# with `git apply --check`, which touches nothing, and only pop when it passes.
# A stash that would conflict is kept — named in the log — for a human to
# resolve, and the tree is left clean at the new HEAD.
restore_stash() {
  local patch
  patch="$(mktemp)"

  if ! git stash show --patch --no-color stash@'{0}' > "$patch" 2>>"$LOG"; then
    rm -f "$patch"
    log "WARNING: could not read the stash back; local changes kept in stash@{0}"
    return 0
  fi

  if ! [ -s "$patch" ]; then
    rm -f "$patch"
    git stash drop --quiet 2>>"$LOG"
    log "stash was empty; dropped"
    return 0
  fi

  if ! git apply --check "$patch" 2>>"$LOG"; then
    rm -f "$patch"
    log "WARNING: local changes CONFLICT with the update — kept in stash@{0}, reapply with: cd $DOTFILES && git stash pop"
    return 0
  fi
  rm -f "$patch"

  if git stash pop --quiet 2>>"$LOG"; then
    log "reapplied local changes"
  else
    log "WARNING: reapplying local changes failed; they are kept in stash@{0}"
  fi
}

# Refresh pi's installed extension packages.
#
# Why this exists: `pi install git:…` clones into ~/.pi/agent/git/… once and
# nothing ever re-pulls it, so a host silently runs whatever the code looked
# like on install day. That cost a long debugging session on 2026-07-25 — a
# 10-day-stale pi-interactive-subagents clone was missing a merged zellij
# pane-id fix, and the symptom (subagents dying with no output) looked for all
# the world like a provider/model bug.
#
# `pi update <source>` fetches and resets that clone to origin/HEAD. Scoped to
# the sources listed in settings.json, deliberately NOT bare `pi update`: that
# also self-updates the globally-installed pi, which can need sudo and should
# stay a deliberate human action rather than a background surprise.
refresh_pi_packages() {
  command -v pi >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || {
    log "pi: skip — jq not installed"
    return 0
  }

  local settings="$DOTFILES/modules/pi/settings.json"
  [ -f "$settings" ] || {
    log "pi: skip — no $settings"
    return 0
  }

  local source
  while IFS= read -r source; do
    [ -n "$source" ] || continue
    if pi update "$source" >>"$LOG" 2>&1; then
      log "pi: refreshed $source"
    else
      log "pi: FAILED to refresh $source"
    fi
  done < <(jq -r '.packages[]? // empty' "$settings")
}

# Keep ~/.gitconfig.github-ssh in step with this host's GitHub SSH key. The
# tracked gitconfig only *includes* that file (see modules/git/gitconfig): the
# HTTPS -> SSH rewrite belongs on hosts whose ssh config has a Host entry for
# github.com (github::set_ssh_key writes one), and must not exist on headless
# workers, which push over HTTPS with a token. Running this daily migrates
# hosts that were provisioned before the rewrite moved out of the tracked
# gitconfig, and converges the file's content if a later commit changes it.
# The generated content must stay byte-identical to setup_github_ssh_rewrite
# in modules/git/setup.sh.
ensure_github_ssh_rewrite() {
  local rewrite="$HOME/.gitconfig.github-ssh" desired
  if grep -qsiE '^[[:space:]]*Host[[:space:]]+([^#]*[[:space:]])?github\.com([[:space:]]|$)' \
    "$HOME/.ssh/config"; then
    desired=$(printf '%s\n' \
      '# Generated by the dotfiles git module (modules/git/setup.sh; ensured daily' \
      '# by modules/dotfiles-autoupdate/update.sh): this host has an authorised' \
      '# GitHub SSH key ("Host github.com" in ~/.ssh/config), so HTTPS remotes' \
      '# rewrite to SSH. See the include comment in modules/git/gitconfig.' \
      '[url "git@github.com:"]' \
      '	insteadOf = https://github.com/')
    if [ ! -f "$rewrite" ] || [ "$(cat "$rewrite")" != "$desired" ]; then
      printf '%s\n' "$desired" >"$rewrite"
      log "wrote $rewrite (host has a GitHub SSH key)"
    fi
  fi
}

update_dotfiles
ensure_github_ssh_rewrite
refresh_pi_packages
