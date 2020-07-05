#!/usr/bin/env bash

setup_ssh_config () {
  local LOCAL_CONFIG=modules/ssh/config
  if ! [ -f $LOCAL_CONFIG ]
  then
    cat \
      $LOCAL_CONFIG.tmpl > $LOCAL_CONFIG

    log::result $? 'generated .ssh/config'
  fi
}

. "$DOTFILES/scripts/core/main.sh"
setup_ssh_config
