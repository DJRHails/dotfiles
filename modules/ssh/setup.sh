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

generate_ssh_key () {
  local keyFileName="$HOME/.ssh/id_$(hostname -s)"

  # If there is alread a file with that name, check with the user
  if [ -f "$keyFileName" ]; then
    keyFileName="$(mktemp -u "$HOME/.ssh/id_$(hostname -s)_XXXXX")"
  fi

  ssh-keygen -o -a 500 -t ed25519 -f "$keyFileName"
}

. "$DOTFILES/scripts/core/main.sh"
setup_ssh_config
