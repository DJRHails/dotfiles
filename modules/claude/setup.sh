#!/usr/bin/env bash

##? Setup Claude Code CLI
##?
##? Installs Claude Code via official installer and sets up the configuration directory.
##? Uses ~/.agents/ as the canonical config directory with ~/.claude/ as a symlink.

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

# Ensure ~/.agents directory exists (symlinks will populate it)
mkdir -p ~/.agents

# Compatibility symlink: ~/.claude -> ~/.agents
if [ -L ~/.claude ]; then
  log::success "~/.claude symlink already exists"
elif [ -d ~/.claude ]; then
  log::info "Migrating ~/.claude/ contents to ~/.agents/"
  # Move any non-symlinked files from .claude to .agents
  for item in ~/.claude/*; do
    [ -e "$item" ] || continue
    base="$(basename "$item")"
    if [ ! -e ~/.agents/"$base" ]; then
      mv "$item" ~/.agents/"$base"
    fi
  done
  rm -rf ~/.claude
  ln -s .agents ~/.claude
  log::success "Migrated ~/.claude/ to ~/.agents/ with symlink"
else
  ln -s .agents ~/.claude
  log::success "Created ~/.claude -> ~/.agents symlink"
fi

# Compatibility symlink: ~/.agents/CLAUDE.md -> AGENTS.md
if [ ! -L ~/.agents/CLAUDE.md ]; then
  ln -sf AGENTS.md ~/.agents/CLAUDE.md
  log::success "Created ~/.agents/CLAUDE.md -> AGENTS.md symlink"
fi

log::success "Claude Code setup complete"
