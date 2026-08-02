# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# GUI terminal — macOS only. The config this module symlinks is useless without
# it, and it has no business being installed by an unrelated module.
install::cask "Ghostty" "ghostty"
