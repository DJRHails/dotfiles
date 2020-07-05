. "$DOTFILES/scripts/core/main.sh"

install::package "ZSH" "zsh"

# Set as default shell
ZSH_SHELL_LOC=$(which zsh)

# This needs to be done because applications use this file to
# determine whether a shell is valid.
# http://www.linuxfromscratch.org/blfs/view/7.4/postlfs/etcshells.html
if ! grep "$ZSH_SHELL_LOC" < /etc/shells &> /dev/null; then
    log::execute \
        "printf '%s\n' '$ZSH_SHELL_LOC' | sudo tee -a /etc/shells" \
        "ZSH (add '$ZSH_SHELL_LOC' in '/etc/shells')"
fi

if [ "$SHELL" != "$ZSH_SHELL_LOC" ]
then
  chsh -s "$ZSH_SHELL_LOC"
  log::result $? "ZSH (use installed version)"
fi

# Install zplug for the next bit
if [[ -z $ZPLUG_HOME ]] && [[ ! -d ~/.zplug ]]; then
  export ZPLUG_HOME=~/.zplug
  git clone --depth 1 https://github.com/zplug/zplug $ZPLUG_HOME
  log::result $? "Clone zplug to $ZPLUG_HOME"
fi

# Install fzf
if [[ -z $FZF_BASE ]] && [[ ! -d ~/.fzf ]]; then
  export FZF_BASE=~/.fzf
  git clone --depth 1 https://github.com/junegunn/fzf.git $FZF_BASE
  log::result $? "Clone fzf to $FZF_BASE"
  $FZF_BASE/install --no-bash --all
  log::result $? "Install fzf"
fi
