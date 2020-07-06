#!/usr/bin/env bash

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Move to the correct directory for duration of this script
cd "$(dirname "${BASH_SOURCE[0]}")" \
  || exit 1
readonly DOTFILES=$(pwd -P)
declare skipQuestions=false

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

parse_args() {
     while [[ $# -gt 0 ]]
     do
        case $1 in
          -y|--yes)
            skipQuestions=true
          ;;
          -A|--all)
            allModules=true
          ;;
          -r|--recommended)
            modules+=("$DOTFILES/modules/zsh" "$DOTFILES/modules/ssh" "$DOTFILES/modules/git")
          ;;
          *)
            modules+=("$DOTFILES/modules/$1")
          ;;
        esac
        shift
    done
}

cmd_exists() {
    command -v "$1" &> /dev/null
}

run() {
  local module_dir=$1
  local script_name=$2
  local src="$1/$2"
  if [ -f $src ]; then
    log::subheader "Executing ${script_name%.*} for '${module_dir##*/}'"
    . $src
    log::result $? "${script_name%.*} completed"
  fi
}

create_links() {
  local module_dir="$1"
  local symlink_file="$module_dir/symlinks.conf"
  local overwrite_all=false backup_all=$skipQuestions skip_all=false

  if [ -f $symlink_file ]; then
    log::subheader "Creating symbolic links for '${module_dir##*/}'"
    link::extract_and_link "$symlink_file"
  fi
}

main() {
  # Load utilities
  . "scripts/core/main.sh"
  . "scripts/scan.sh"
  . "scripts/link.sh"

  # Check for arguments
  modules=()
  allModules=false
  skipQuestions=false
  parse_args "$@"

  # Splash Screen
  log::splash " Bootstrapping .files from $DOTFILES"

  # Verify OS
  log::header "Verify OS verion\n"
  platform::is_supported && log::success "$os_name with v$os_version is valid"

  # Grab modules
  scan::find_valid_modules modules

  log::header "Installing $(log::bold "${#modules[@]} modules")"

  platform::ask_for_sudo

  for idx in "${!modules[@]}"
  do
    local module_dir="${modules[$idx]}"
    if [[ ! -z $module_dir ]]; then
      log::header "$((idx+1)). Running '${module_dir##*/}'"
      run "$module_dir" "setup.sh"
      create_links "$module_dir"
      run "$module_dir" "install.sh"
      run "$module_dir" "install.$(platform::os).sh"
      export ${module_dir##*/}=installed
    fi
  done

  . "scripts/restart.sh"
}

main "$@"
