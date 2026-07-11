#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

link::file () {
  local src=$1 dst=$2

  local overwrite='' backup='' skip=''

  if [ -f "$dst" ] || [ -d "$dst" ] || [ -L "$dst" ]
  then
    # Already linked to the correct target — return immediately.
    # Must return before the backup_all fallthrough which would
    # mv the correct symlink to .backup then skip re-creation.
    if [ -L "$dst" ] && [ "$(readlink "$dst")" == "$src" ]; then
      log::success "skipped $src (already linked)"
      return
    elif [ "$overwrite_all" == "false" ] && [ "$backup_all" == "false" ] && [ "$skip_all" == "false" ]
    then
      local currentSrc
      currentSrc="$(readlink "$dst")"

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
    log::result $? "linked $1 to $2"
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

  link::prune_stale "$1"
}

# Remove symlinks left behind by earlier revisions of a symlinks.conf: a link
# that lives in one of the conf's destination directories and points into this
# module's dir, but is no longer declared, is drift (renamed/removed conf
# entries otherwise linger on every machine forever). Links owned by other
# modules or created by hand point elsewhere and are never touched, and the
# linker's own *.backup copies are spared.
link::prune_stale() {
  local conf=$1
  # Match on the same literal prefix link::file writes (dirname of the conf),
  # with the physical path as a fallback for links made from a resolved cwd.
  local module_dir module_dir_phys
  module_dir="$(dirname "$conf")"
  module_dir_phys="$(cd "$module_dir" && pwd -P)"

  local -A declared=()
  local -A parents=()
  local sep=' -> '
  local line dst
  while read -r line || [[ -n "$line" ]]
  do
    [[ -z "$line" || "$line" == \#* ]] && continue
    dst=${line#*$sep}
    dst=${dst/#\~/$HOME}
    declared["$dst"]=1
    parents["$(dirname "$dst")"]=1
  done < "$conf"

  local dir entry target
  for dir in "${!parents[@]}"
  do
    [ -d "$dir" ] || continue
    while IFS= read -r entry
    do
      [[ -n "${declared[$entry]:-}" ]] && continue
      case "$entry" in *.backup | *.backup.*) continue ;; esac
      target=$(readlink "$entry")
      case "$target" in
        "$module_dir"/* | "$module_dir_phys"/*)
          rm "$entry"
          log::success "pruned stale link $entry (was -> $target)"
          ;;
      esac
    done < <(find "$dir" -maxdepth 1 -type l 2>/dev/null)
  done
}
