#!/usr/bin/env bash

##? Setup Claude Code CLI
##?
##? Installs Claude Code via official installer and sets up the configuration directory.

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

# Ensure .claude directory exists (symlinks will populate it)
mkdir -p ~/.claude

# Copy global config template if local copy doesn't exist
local_claude_config="$MODULE_DIR/claude.json"
if [ ! -f "$local_claude_config" ]; then
  log::info "Creating $local_claude_config from template..."
  cp "$MODULE_DIR/claude.json.tmpl" "$local_claude_config"
  log::result $? "Created $local_claude_config"
else
  log::success "Local config already exists: $local_claude_config"
fi

log::success "Claude Code setup complete"
