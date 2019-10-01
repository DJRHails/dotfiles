#!/usr/bin/env bash

execute_for_all_modules() {
  local script_name=$1
  shift
  local scripts=("$@")

  for idx in "${!scripts[@]}"
  do
    local src="${scripts[$idx]}"
    module_name="$(basename "$(dirname "$src")")"
    log::subheader "$((idx+1)). Executing ${script_name%.*} for '$module_name'"
    . $src
    log::result $? "${script_name%.*} completed"
  done
}

find_matching_scripts() {
  local -n found_scripts=$2
  while IFS=  read -r -d $'\0'; do
      found_scripts+=("$REPLY")
  done < <(find -H "$DOTFILES" -maxdepth 2 -name "$1" -print0)
}

main() {
  scripts=()
  find_matching_scripts $1 scripts

  if [ -n "$scripts" ]
  then
    log::header "Running '${1}' in $(log::bold "${#scripts[@]} modules")"
    execute_for_all_modules $1 "${scripts[@]}"
  fi
}

. "$DOTFILES/scripts/core/main.sh"
main $@
