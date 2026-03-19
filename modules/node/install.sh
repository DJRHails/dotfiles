# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

install::package "Node.js" "node"

if command -v pnpm &>/dev/null; then
  log::success "pnpm"
else
  log::execute "npm install -g pnpm" "pnpm"
fi
