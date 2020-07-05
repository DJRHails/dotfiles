#!/usr/bin/env bash
install::with() {
  local -r PACKAGE_READABLE_NAME="$1"
  local -r PACKAGE="$2"
  local -r EXTRA_ARGUMENTS="$3"
  local -r PACKAGE_MANAGER="$4"

  if ! platform::command_exists "$PACKAGE"; then
    log::execute "$PACKAGE_MANAGER install $EXTRA_ARGUMENTS $PACKAGE" "$PACKAGE_READABLE_NAME"
  else
    log::success "$PACKAGE_READABLE_NAME"
  fi
}

install::package() {
  install::with ${1:-''} ${2:-''} ${3:-''} "$(platform::main_package_manager)"
}

install::snap() {
  install::with ${1:-''} ${2:-''} ${3:-''} "sudo snap"
}

install::cask() {
  install::with ${1:-''} ${2:-''} ${3:-''} "brew cask"
}
