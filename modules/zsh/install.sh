. "$DOTFILES/scripts/core/main.sh"

# Ensure ~/.local/bin is on PATH for tools installed there
[[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

install::package "ZSH" "zsh"

# Set as default shell
ZSH_SHELL_LOC=$(which zsh)

# This needs to be done because applications use this file to
# determine whether a shell is valid.
# http://www.linuxfromscratch.org/blfs/view/7.4/postlfs/etcshells.html
if ! grep "$ZSH_SHELL_LOC" < /etc/shells &> /dev/null; then
    log::execute \
        "printf '%s\n' '$ZSH_SHELL_LOC' | $(platform::sudo_prefix)tee -a /etc/shells" \
        "ZSH (add '$ZSH_SHELL_LOC' in '/etc/shells')"
fi

if [ "$SHELL" != "$ZSH_SHELL_LOC" ]
then
  platform::sudo chsh -s "$ZSH_SHELL_LOC" "$(whoami)" 2>/dev/null \
    || chsh -s "$ZSH_SHELL_LOC" 2>/dev/null
  log::result $? "ZSH (use installed version)"
fi

# Install sheldon plugin manager
if ! cmd_exists sheldon; then
  curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
    | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
  log::result $? "sheldon"
fi

# Install starship prompt
if ! cmd_exists starship; then
  mkdir -p ~/.local/bin
  curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir ~/.local/bin
  log::result $? "starship"
fi

# Install fzf
if [[ -z $FZF_BASE ]] && [[ ! -d ~/.fzf ]]; then
  export FZF_BASE=~/.fzf
  git clone --depth 1 https://github.com/junegunn/fzf.git $FZF_BASE
  log::result $? "Clone fzf to $FZF_BASE"
  $FZF_BASE/install --no-bash --all
  log::result $? "Install fzf"
fi
