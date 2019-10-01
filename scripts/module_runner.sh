#!/usr/bin/env bash

execute_for_all_modules() {
  module_scripts=$2
  for idx in "${!module_scripts[@]}"
  do
    local src="${module_scripts[$idx]}"
    module_name="$(basename "$(dirname "$src")")"
    log::subheader "$((idx+1)). Executing ${1%.*} for '$module_name'"
    . $src
    log::result $? "${1%.*} completed"
  done
}

main() {
  matching_scripts=$(find -H "$DOTFILES" -maxdepth 2 -name "${1}" -not -path '*.git*')

  if [ -n "$matching_scripts" ]
  then
    log::header "Running '${1}' in $(log::bold "${#matching_scripts[@]} modules")"
    execute_for_all_modules $1 $matching_scripts
  fi
}

. "$DOTFILES/scripts/core/main.sh"
main $@
