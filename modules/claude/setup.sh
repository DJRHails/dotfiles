#!/usr/bin/env bash

##? Setup Claude Code CLI
##?
##? Installs Claude Code via official installer and sets up the configuration directory.
##? Config lives in modules/claude/ (Claude-specific) and modules/agents/ (shared).
##? symlinks.conf links into ~/.claude/ and ~/.agents/.

. "$DOTFILES/scripts/core/main.sh"

# Install Claude Code CLI
if ! cmd_exists claude; then
  log::info "Installing Claude Code CLI..."
  CLAUDE_INSTALLER="$(mktemp)"
  curl -fsSL https://claude.ai/install.sh -o "$CLAUDE_INSTALLER" && bash "$CLAUDE_INSTALLER"
  log::result $? "Claude Code CLI installed"
  rm -f "$CLAUDE_INSTALLER"
else
  log::success "Claude Code CLI already installed"
  claude --version 2>/dev/null || true
fi

# Ensure target directories exist (symlinks.conf populates them)
mkdir -p ~/.claude ~/.agents

# Materialise settings as real files, tracked defaults merged over the app's own
# writes. Claude Code persists a `/model` switch into its settings file, so these
# cannot be symlinks into the repo: one `/model` rewrote the tracked default and
# left every host's dotfiles tree dirty, which silently parked the daily
# autoupdate for a week. Tracked keys win, app-only keys survive, so `/model`
# holds for the session and the committed default is restored on the next
# bootstrap.
merge_settings() {
  local tracked=$1 dest=$2 merged
  if [ ! -f "$dest" ] || [ -L "$dest" ]; then
    rm -f "$dest"
    cp "$tracked" "$dest"
    log::success "wrote ${dest/#$HOME/~} (from ${tracked##*/})"
    return
  fi
  merged="$(mktemp)"
  if ! jq -s '.[0] * .[1]' "$dest" "$tracked" > "$merged"; then
    rm -f "$merged"
    log::error "could not merge ${tracked##*/} into ${dest/#$HOME/~} (invalid JSON?)"
    return 1
  fi
  if cmp -s "$merged" "$dest"; then
    rm -f "$merged"
    log::success "skipped ${dest/#$HOME/~} (already matches ${tracked##*/})"
  else
    mv "$merged" "$dest"
    log::success "merged ${tracked##*/} into ${dest/#$HOME/~}"
  fi
}

if platform::command_exists jq; then
  merge_settings "$DOTFILES/modules/claude/settings.json" "$HOME/.agents/settings.json"
  merge_settings "$DOTFILES/modules/claude/settings.json" "$HOME/.claude/settings.json"
  for profile in "$HOME/.claude-ant" "$HOME/.claude-ant-safe"; do
    [ -d "$profile" ] || continue
    merge_settings "$DOTFILES/modules/claude/settings.ant.json" "$profile/settings.json"
  done
else
  log::warning "jq not on PATH; skipping settings merge (install.sh installs it)"
fi

log::success "Claude Code setup complete"
