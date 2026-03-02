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

propagate_terminfo() {
  local term="${TERM:-xterm-256color}"

  # Standard terminals already exist in remote terminfo databases
  case "$term" in
    xterm|xterm-256color|screen*|tmux*|vt*|dumb|linux)
      return 0 ;;
  esac

  if ! command -v infocmp &>/dev/null; then
    log::warning "infocmp not found, skipping terminfo propagation"
    return 0
  fi

  log::subheader "Propagating $term terminfo to SSH hosts"

  local host
  while IFS= read -r host; do
    if infocmp -x "$term" 2>/dev/null \
        | ssh -o ConnectTimeout=3 -o BatchMode=yes \
              "$host" tic -x - 2>/dev/null; then
      log::success "propagated $term terminfo → $host"
    else
      log::info "skipped $host (unreachable)"
    fi
  done < <(
    awk '/^Host / { for (i=2; i<=NF; i++) print $i }' \
      modules/ssh/config \
      | grep -v '[*?]' \
      | grep -v 'github.com'
  )
}

. "$DOTFILES/scripts/core/main.sh"
setup_ssh_config
propagate_terminfo
