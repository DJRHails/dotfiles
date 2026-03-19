#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

link::file () {
  local src=$1 dst=$2

  local overwrite= backup= skip=
  local action=

  if [ -f "$dst" -o -d "$dst" -o -L "$dst" ]
  then
    # Already linked to the correct target — return immediately.
    # Must return before the backup_all fallthrough which would
    # mv the correct symlink to .backup then skip re-creation.
    if [ -L "$dst" ] && [ "$(readlink "$dst")" == "$src" ]; then
      log::success "skipped $src (already linked)"
      return
    elif [ "$overwrite_all" == "false" ] && [ "$backup_all" == "false" ] && [ "$skip_all" == "false" ]
    then
      local currentSrc="$(readlink $dst)"

      if [ "$currentSrc" == "$src" ]
      then
        skip=true;
      else
        feedback::ask "File already exists: $dst (${src##*/})), what do you want to do?\n\
        [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all?"

        case "$(feedback::get_answer)" in
          o )
            overwrite=true;;
          O )
            overwrite_all=true;;
          b )
            backup=true;;
          B )
            backup_all=true;;
          s )
            skip=true;;
          S )
            skip_all=true;;
          * )
            ;;
        esac
      fi
    fi

    overwrite=${overwrite:-$overwrite_all}
    backup=${backup:-$backup_all}
    skip=${skip:-$skip_all}

    if [ "$overwrite" == "true" ]
    then
      rm -rf "$dst"
      log::success "removed $dst"
    fi

    if [ "$backup" == "true" ]
    then
      # Rename existing backup with timestamp so mv doesn't try to
      # move dst INTO an existing backup directory.
      if [ -e "${dst}.backup" ]; then
        mv "${dst}.backup" "${dst}.backup.$(date +%Y%m%d%H%M%S)"
      fi
      mv "$dst" "${dst}.backup"
      log::success "moved $dst to ${dst}.backup"
    fi

    if [ "$skip" == "true" ]
    then
      log::success "skipped $src"
    fi
  fi

  if [ "$skip" != "true" ]  # "false" or empty
  then
    mkdir -p "$(dirname "$2")"
    ln -s "$1" "$2"
    log::success "linked $1 to $2"
  fi
}

link::extract_and_link() {
  local sep=' -> '
  while read -r line || [[ -n "$line" ]]
  do
    [[ -z "$line" ]] && continue
    local src=${line%%$sep*}
    local dst=${line#*$sep}
    link::file "$(dirname "$1")/$src" "${dst/#\~/$HOME}"
  done < "$1"
}
