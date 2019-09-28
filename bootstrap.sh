#!/usr/bin/env bash

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

readonly DOTFILES_ROOT=$(pwd -P)
declare skipQuestions=false

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

main() {

  echo "Installing .files from $DOTFILES_ROOT"
  # Load utilities
  . "script/utils.sh"

  . "script/verify_os.sh"

  # Check if iteractive
  skip_questions "$@" \
    && skipQuestions=true

  # TODO: If needs sudo, ask here

  . "script/module_runner.sh" "setup.sh"
  . "script/create_symbolic_links.sh"

  . "script/module_runner.sh" "install.sh"
  . "script/module_runner.sh" "install.$(get_os).sh"

  #
  # ./preferences/main.sh
  . "script/restart.sh"
}

# Move to the correct directory for duration of this script
cd "$(dirname "${BASH_SOURCE[0]}")" \
  || exit 1
main "$@"
