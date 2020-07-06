. "$DOTFILES/scripts/core/main.sh"

install::package "fd" "fd-find"
platform::relink "fdfind" "fd"
