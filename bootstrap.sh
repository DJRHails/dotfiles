#!/usr/bin/env bash

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Move to the correct directory for duration of this script
cd "$(dirname "${BASH_SOURCE[0]}")" \
  || exit 1
readonly DOTFILES=$(pwd -P)
declare skipQuestions=false

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

skip_questions() {
     while :; do
        case $1 in
            -y|--yes) return 0;;
                   *) break;;
        esac
        shift 1
    done

    return 1
}

cmd_exists() {
    command -v "$1" &> /dev/null
}

main() {

  echo "Installing .files from $DOTFILES"
  # Load utilities
  . "scripts/core/main.sh"

  . "scripts/verify_os.sh"

  # Check if iteractive
  skip_questions "$@" \
    && skipQuestions=true

  # TODO: If needs sudo, ask here

  . "scripts/module_runner.sh" "setup.sh"
  . "scripts/create_symbolic_links.sh"

  . "scripts/module_runner.sh" "install.sh"
  . "scripts/module_runner.sh" "install.$(get_os).sh"

  #
  # ./preferences/main.sh
  . "scripts/restart.sh"
}

main "$@"
