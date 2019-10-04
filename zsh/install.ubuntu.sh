. "$DOTFILES/scripts/core/main.sh"

apt install zsh
log::result $? "Install Zsh"

chsh -s $(which zsh)
log::result $? "Set Zsh as default shell"
