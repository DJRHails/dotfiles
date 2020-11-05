#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

scan::find_matching_scripts() {
  local scriptName="$1"
  local searchDir="${2:-"$DOTFILES/modules"}"
  while IFS=  read -r -d $'\0'
  do
    matching_scripts+=("$REPLY")
  done < <(find -H "$searchDir" -mindepth 1 -maxdepth 2 -name "$scriptName" -print0)
}

scan::find_modules() {
  scanned_modules=()
  local searchDir="${1:-"$DOTFILES/modules"}"
  while IFS=  read -r -d $'\0'
  do
    # Only add if new.
    if [[ ! " ${scanned_modules[@]} " =~ " $REPLY " ]]
    then
      scanned_modules+=("$REPLY")
    fi
  done < <(find -H "$searchDir" -mindepth 1 -maxdepth 1 -type d -print0)
  log::header "Found $(log::bold "${#scanned_modules[@]} modules")"
}

# Uses skipQuestions & allModules
scan::find_valid_modules() {

  if [ "$allModules" = true ]
  then
    scan::find_modules
    scanned_valid_modules = scanned_modules
    return
  fi

  if [ "$skipQuestions" = true ]
  then
    # Here we don't add anything, as modules wanted are already set.
    return
  fi

  scan::find_modules
  for moduleDir in ${scanned_modules[@]}
  do
    # If it wasn't already present, ask if we want to install it
    if [[ ! " ${scanned_valid_modules[@]} " =~ " $moduleDir " ]]
    then
      feedback::ask_for_confirmation "Do you want to execute '${moduleDir##*/}'"
      if feedback::answer_is_yes
      then
        scanned_valid_modules+=("$moduleDir")
      fi
    fi
  done
}
