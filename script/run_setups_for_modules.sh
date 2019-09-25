#!/usr/bin/env bash

setup_modules() {
  for src in $(find -H "$DOTFILES_ROOT" -maxdepth 2 -name '*setup.sh' -not -path '*.git*')
  do
    print_in_purple "   Setting up $(basename $(dirname "${src%.*}"))\n"
    . $src
    print_result $? "Setup $(basename "${src%.*}")"
  done
}

main() {
  print_in_purple "\n • Running module setups\n\n"
  setup_modules
}

. "$DOTFILES_ROOT/script/utils.sh"
main
