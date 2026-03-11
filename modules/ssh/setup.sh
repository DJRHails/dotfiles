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
  local keyFileName
  keyFileName="$HOME/.ssh/id_$(hostname -s)"

  # If there is already a file with that name, check with the user
  if [ -f "$keyFileName" ]; then
    keyFileName="$(mktemp -u "$HOME/.ssh/id_$(hostname -s)_XXXXX")"
  fi

  ssh-keygen -o -a 500 -t ed25519 -f "$keyFileName"
}

install_terminfo() {
  local terminfo_dir="modules/ssh/terminfo"
  if ! [ -d "$terminfo_dir" ]; then
    return 0
  fi

  local src
  for src in "$terminfo_dir"/*.terminfo; do
    [ -f "$src" ] || continue
    if tic -x "$src" 2>/dev/null; then
      log::success "installed terminfo: $(basename "$src" .terminfo)"
    else
      log::warning "failed to compile terminfo: $(basename "$src")"
    fi
  done
}

# shellcheck source=/dev/null
. "$DOTFILES/scripts/core/main.sh"
setup_ssh_config
install_terminfo
