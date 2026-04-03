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
  curl -fsSL https://claude.ai/install.sh | bash
  log::result $? "Claude Code CLI installed"
else
  log::success "Claude Code CLI already installed"
  claude --version 2>/dev/null || true
fi

# Ensure target directories exist (symlinks.conf populates them)
mkdir -p ~/.claude ~/.agents

log::success "Claude Code setup complete"
