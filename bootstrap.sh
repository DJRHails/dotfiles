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

  # ./install/main.sh
  #
  # ./preferences/main.sh
}

# Move to the correct directory for duration of this script
cd "$(dirname "${BASH_SOURCE[0]}")" \
  || exit 1
main "$@"
