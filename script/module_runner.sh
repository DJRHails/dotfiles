#!/usr/bin/env bash

execute_for_all_modules() {
  for src in $2
  do
    module_name="$(basename "$(dirname "$src")")"
    print_in_purple "   Executing ${1} for '$module_name'\n"
    . $src
    print_result $? "${1} completed"
  done
}

main() {
  matching_scripts=$(find -H "$DOTFILES_ROOT" -maxdepth 2 -name "${1}.sh" -not -path '*.git*')

  if [ -n "$matching_scripts" ]
  then
    execute_for_all_modules $@ $matching_scripts
  fi
}

. "$DOTFILES_ROOT/script/utils.sh"
main $@
