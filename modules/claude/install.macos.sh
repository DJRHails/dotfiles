# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# GUI terminal — macOS only. The CLI tools (actionlint, zizmor, …) are now
# cross-platform in install.sh; Node + pnpm live in the `node` module.
install::cask "Ghostty" "ghostty"
