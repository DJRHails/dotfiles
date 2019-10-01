#!/usr/bin/env bash

setup_zshrc () {
  if ! [ -f zsh/zshrc ]
  then
    sed -e "s+DOTFILES+$DOTFILES+g" \
      zsh/zshrc.example > zsh/zshrc

    log::result $? 'generated zsh/zshrc'
  fi

  local LOCAL_ZSHRC=zsh/zshrc.local
  if ! [ -f $LOCAL_ZSHRC ]
  then
    feedback::ask " - Where are you going to store your projects? ($HOME/projects)"
    local project_dir="$(feedback::get_answer)"
    project_dir=${project_dir:-"$HOME/projects"}

    sed -e "s+PROJECT_ROOT+$project_dir+g" \
      $LOCAL_ZSHRC.example > $LOCAL_ZSHRC

    log::result $? 'generated zsh/zshrc'
  fi
}

. "$DOTFILES/scripts/core/main.sh"
setup_zshrc
