. "$DOTFILES/scripts/core/main.sh"

install::package "Zellij" "zellij"

# humane CLI — auto-attach.zsh / mosh-zellij.zsh use `humane id` for readable session names.
if command -v uv >/dev/null 2>&1; then
  command -v humane >/dev/null 2>&1 || uv tool install humane
fi
