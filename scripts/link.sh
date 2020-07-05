#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

link::file () {
  local src=$1 dst=$2

  local overwrite= backup= skip=
  local action=

  if [ -f "$dst" -o -d "$dst" -o -L "$dst" ]
  then
    if [ "$overwrite_all" == "false" ] && [ "$backup_all" == "false" ] && [ "$skip_all" == "false" ]
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
    ln -s "$1" "$2"
    log::success "linked $1 to $2"
  fi
}

link::extract_and_link() {
  declare -A links
  local sep=' -> '
  while read line
  do
    src=${line%%$sep*}
    dst=${line#*$sep}
    links[$src]=$dst
  done < $1

  for src in ${!links[*]}
  do
    link::file "$(dirname $1)/$src" "${links[$src]/#\~/$HOME}"
  done
}
