. "$DOTFILES/scripts/core/main.sh"

install::package "jq" "jq"
install::package "ripgrep" "ripgrep"
install::package "fd" "fd"
install::package "ast-grep" "ast-grep"
install::package "shellcheck" "shellcheck"
install::package "shfmt" "shfmt"
if platform::is_osx; then
  install::package "macos-trash" "macos-trash"
elif platform::is_linux; then
  install::package "trash-cli" "trash-cli"
fi
