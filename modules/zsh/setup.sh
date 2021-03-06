#!/usr/bin/env bash

setup_zshrc () {
  sed -e "s+DOTFILES_+$DOTFILES+g" \
    modules/zsh/zshrc.tmpl > modules/zsh/zshrc

  log::result $? 'generated modules/zsh/zshrc'

  local LOCAL_ZSHRC=modules/zsh/zshrc.local
  if ! [ -f $LOCAL_ZSHRC ]
  then
    feedback::ask " - Where are you going to store your projects? ($HOME/projects)"
    local project_dir="$(feedback::get_answer)"
    project_dir=${project_dir:-"$HOME/projects"}

    feedback::ask " - Where are you going to store your sites? ($HOME/sites)"
    local sites_dir="$(feedback::get_answer)"
    sites_dir=${sites_dir:-"$HOME/sites"}

    sed -e "s+PROJECT_ROOT+$project_dir+g;s+SITES_ROOT+$sites_dir+g" \
      $LOCAL_ZSHRC.tmpl > $LOCAL_ZSHRC

    log::result $? 'generated modules/zsh/zshrc'
  fi
}

. "$DOTFILES/scripts/core/main.sh"
setup_zshrc
