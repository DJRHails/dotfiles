#!/usr/bin/env bash

setup_zshrc () {
  if ! [ -f zsh/zshrc.local.symlink ]
  then

    ask " - Where are you keeping your dotfiles? ($DOTFILES_ROOT)"
    local dotfiles="$(get_answer)"
    dotfiles=${dotfiles:-"$DOTFILES_ROOT"}

    ask " - Where are you going to store your projects? ($HOME/projects)"
    local project_dir="$(get_answer)"
    project_dir=${project_dir:-"$HOME/projects"}

    sed -e "s+DOTFILES_ROOT+$dotfiles+g" -e "s+PROJECT_ROOT+$project_dir+g" \
      zsh/zshrc.symlink.example > zsh/zshrc.symlink

    print_result $? 'generated zsh/zshrc.symlink'
  fi
}


. "$DOTFILES_ROOT/script/utils.sh"
setup_zshrc
