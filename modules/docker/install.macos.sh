# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Colima — lightweight container runtime (replaces Docker Desktop)
if command -v colima &>/dev/null; then
  log::success "Colima"
else
  log::execute "brew install colima" "Colima"
fi

# Docker CLI + Compose plugin (no Docker Desktop)
if command -v docker &>/dev/null; then
  log::success "Docker CLI"
else
  log::execute "brew install docker" "Docker CLI"
fi

if docker compose version &>/dev/null; then
  log::success "Docker Compose"
else
  log::execute "brew install docker-compose" "Docker Compose plugin"
fi

# Docker credential helper for macOS keychain
if command -v docker-credential-osxkeychain &>/dev/null; then
  log::success "Docker credential helper"
else
  log::execute "brew install docker-credential-helper" "Docker credential helper"
fi
