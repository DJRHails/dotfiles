#!/usr/bin/env bash

execute_for_all_modules() {
  module_scripts=$2
  for idx in "${!module_scripts[@]}"
  do
    local src="${module_scripts[$idx]}"
    module_name="$(basename "$(dirname "$src")")"
    print_in_purple "   $((idx+1)). Executing ${1%.*} for '$module_name'\n"
    . $src
    print_result $? "${1%.*} completed"
  done
}

main() {
  matching_scripts=$(find -H "$DOTFILES_ROOT" -maxdepth 2 -name "${1}" -not -path '*.git*')

  if [ -n "$matching_scripts" ]
  then
    print_in_purple "\n • Running '${1}' in $(print_in_bold "${#matching_scripts[@]} modules")\n"
    execute_for_all_modules $1 $matching_scripts
  fi
}

. "$DOTFILES_ROOT/script/utils.sh"
main $@
