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
  git clone --depth 1 https://github.com/zplug/zplug $ZPLUG_HOME
  log::result $? "Clone zplug to $ZPLUG_HOME"
fi

# Install fzf
if [[ -z $FZF_BASE ]]; then
  export FZF_BASE=~/.fzf
  git clone --depth 1 https://github.com/junegunn/fzf.git $FZF_BASE
  log::result $? "Clone fzf to $FZF_BASE"
  $FZF_BASE/install --no-bash --all
  log::result $? "Install fzf"
fi
