# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# 1Password desktop app plus the `op` CLI — macOS only. The SSH agent lives in
# the desktop app; the CLI is how scripts pull secrets at runtime instead of
# keeping them in .env files. Neither cask installs a command named after the
# cask, so probe the app bundle and the CLI binary directly rather than going
# through install::cask.
if [ -d "/Applications/1Password.app" ]; then
  log::success "1Password app"
else
  brew install --cask 1password
  log::result $? "1Password app"
fi

if platform::command_exists op; then
  log::success "1Password CLI"
else
  brew install --cask 1password-cli
  log::result $? "1Password CLI"
fi
