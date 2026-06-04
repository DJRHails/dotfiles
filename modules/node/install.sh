# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Node 22 LTS on both platforms. Skip if a new-enough node is already present.
if platform::command_exists node \
  && node --version | grep -qE '^v(2[2-9]|[3-9][0-9])\.'; then
  log::success "Node.js $(node --version)"
elif platform::is_osx; then
  install::package "Node.js 22" "node@22"
  brew link --overwrite --force node@22 >/dev/null 2>&1 || true
else
  log::info "Installing Node.js 22 (NodeSource)..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
  install::package "Node.js" "nodejs"
fi

# pnpm via corepack (bundled with Node ≥16); npm global as a fallback. brew's
# node bin dir is user-writable, so only Linux's system prefix needs sudo.
if platform::command_exists pnpm; then
  log::success "pnpm"
elif platform::is_osx; then
  corepack enable pnpm 2>/dev/null || npm install -g pnpm
  log::result $? "pnpm"
else
  sudo corepack enable pnpm 2>/dev/null || sudo npm install -g pnpm
  log::result $? "pnpm"
fi
