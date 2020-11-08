#!/usr/bin/env bash

##? Setup .files and install asked for modules
##?
##? USAGE:
##?    ./bootstrap.sh [FLAGS] [<modules>...]
##? 
##? FLAGS:
##?     -y, --yes  Skip any interactive questions asked during setup.
##?     -A, --all  Run all modules found in $DOTFILES/modules.
##?     -c, --cli  Install only cli modules, perfect for servers.
##?
##? ARGS:
##?     <modules>...  the modules to install (optional)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Move to the correct directory for duration of this script
cd "$(dirname "${BASH_SOURCE[0]}")" \
  || exit 1
readonly DOTFILES=$(pwd -P)

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
          -c|--cli)
            scanned_valid_modules+=("$DOTFILES/modules/zsh" "$DOTFILES/modules/ssh" "$DOTFILES/modules/git")
          ;;
          *)
            scanned_valid_modules+=("$DOTFILES/modules/$1")
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

  # Check if we need help
  doc::maybe_help "$@"

  # Check for arguments
  scanned_valid_modules=()
  allModules=false
  skipQuestions=false
  parse_args "$@"

  # Splash Screen
  log::splash " Bootstrapping .files from $DOTFILES"

  # Verify OS
  log::header "Verify OS verion\n"
  platform::is_supported && log::success "$os_name with v$os_version is valid"

  # Grab modules
  scan::find_valid_modules

  log::header "Installing $(log::bold "${#scanned_valid_modules[@]} modules")"

  platform::ask_for_sudo

  for idx in "${!scanned_valid_modules[@]}"
  do
    local module_dir="${scanned_valid_modules[$idx]}"
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
