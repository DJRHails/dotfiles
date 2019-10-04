. "$DOTFILES/scripts/core/main.sh"

# Check version exisiting
if ! platform::command_exists "zsh"
then
  # Install zsh and zsh-completions
  brew install zsh zsh-completions
  log::result $? "Install zsh"
fi

# Set as default shell
ZSH_SHELL_LOC=/bin/zsh
if [ "$SHELL" != "$ZSH_SHELL_LOC" ]
then
  chsh -s /bin/zsh
  log::result $? "Set Zsh as default shell"
fi

# Install zplug for the next bit
if [[ -z $ZPLUG_HOME ]]; then
  export ZPLUG_HOME=~/.zplug
  git clone https://github.com/zplug/zplug $ZPLUG_HOME
  log::result $? "Clone zplug to $ZPLUG_HOME"
fi

# Install fira code
brew tap homebrew/cask-fonts
brew cask install font-fira-code

# TODO: Install hyper
# TODO: brew cask install hyper
# TODO: > hyper i hyper-snazzy

# REFER TO: https://github.com/StefanScherer/dotfiles
