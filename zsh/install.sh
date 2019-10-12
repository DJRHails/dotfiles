. "$DOTFILES/scripts/core/main.sh"

# Check version exisiting
if ! platform::command_exists "zsh"
then
  $(platform::main_package_manager) install zsh
  log::result $? "Install zsh"
fi

# Set as default shell
ZSH_SHELL_LOC=$(which zsh)
if [ "$SHELL" != "$ZSH_SHELL_LOC" ]
then
  chsh -s "$ZSH_SHELL_LOC"
  log::result $? "Set Zsh as default shell"
fi

# Install zplug for the next bit
if [[ -z $ZPLUG_HOME ]]; then
  export ZPLUG_HOME=~/.zplug
  git clone https://github.com/zplug/zplug $ZPLUG_HOME
  log::result $? "Clone zplug to $ZPLUG_HOME"
fi