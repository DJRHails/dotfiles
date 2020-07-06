#!/usr/bin/env bash

install::with() {
  local -r PACKAGE_MANAGER="$1"
  local -r PACKAGE_READABLE_NAME="$2"
  local -r PACKAGE="$3"
  local -r EXTRA_ARGUMENTS="$4"
  
  if ! platform::command_exists "$PACKAGE"; then
    log::execute "$PACKAGE_MANAGER install $EXTRA_ARGUMENTS $PACKAGE" "$PACKAGE_READABLE_NAME"
  else
    log::success "$PACKAGE_READABLE_NAME"
  fi
}

install::package() {
  install::with "$(platform::package_manager_prefix)$(platform::main_package_manager)" "$1" "$2" "$3"
}

install::snap() {
  install::with "sudo snap" "$1" "$2" "$3"
}

install::cask() {
  install::with "brew cask" "$1" "$2" "$3"
}
