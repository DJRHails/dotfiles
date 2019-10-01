#!/usr/bin/env bash

setup_zshrc () {
  if ! [ -f zsh/zshrc.local.symlink ]
  then

    feedback::ask " - Where are you keeping your dotfiles? ($DOTFILES)"
    local dotfiles="$(feedback::get_answer)"
    dotfiles=${dotfiles:-"$DOTFILES"}

    feedback::ask " - Where are you going to store your projects? ($HOME/projects)"
    local project_dir="$(feedback::get_answer)"
    project_dir=${project_dir:-"$HOME/projects"}

    sed -e "s+DOTFILES+$dotfiles+g" -e "s+PROJECT_ROOT+$project_dir+g" \
      zsh/zshrc.symlink.example > zsh/zshrc.symlink

    log::result $? 'generated zsh/zshrc.symlink'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
setup_zshrc
