#!/usr/bin/env bash

install::with() {
  local -r PACKAGE_MANAGER="$1"
  local -r PACKAGE_READABLE_NAME="$2"
  local -r PACKAGE="$3"
  local EXTRA_ARGUMENTS="$4"
  
  # Inject extra arguments if not provided
  if [ -z "$EXTRA_ARGUMENTS" ]; then
    EXTRA_ARGUMENTS=$(platform::main_package_args)
  fi

  if ! platform::command_exists "$PACKAGE"; then
    log::execute "$PACKAGE_MANAGER install $EXTRA_ARGUMENTS $PACKAGE" "$PACKAGE_READABLE_NAME"
  else
    log::success "$PACKAGE_READABLE_NAME"
  fi
}

install::package_manager() {
  echo "$(platform::package_manager_prefix)$(platform::main_package_manager)"
}

install::package() {
  install::with "$(install::package_manager)" "$1" "$2" "$3"
}

install::snap() {
  install::with "sudo snap" "$1" "$2" "$3"
}

install::cask() {
  install::with "brew" "$1" "$2" "$3" "--cask"
}
