#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

scan::find_matching_scripts() {
  local scriptName="$1"
  local -n returnArrayValidScripts=$2
  local searchDir="${3:-"$DOTFILES/modules"}"
  while IFS=  read -r -d $'\0'
  do
    returnArrayValidScripts+=("$REPLY")
  done < <(find -H "$searchDir" -mindepth 1 -maxdepth 2 -name "$scriptName" -print0)
}

scan::find_modules() {
  local -n returnModules=$1
  local searchDir="${3:-"$DOTFILES/modules"}"
  while IFS=  read -r -d $'\0'
  do
    # Only add if new.
    if [[ ! " ${returnModules[@]} " =~ " $REPLY " ]]
    then
      returnModules+=("$REPLY")
    fi
  done < <(find -H "$searchDir" -type d -mindepth 1 -maxdepth 1 -print0)
  log::header "Found $(log::bold "${#returnModules[@]} modules")"
}

# Uses skipQuestions & allModules
scan::find_valid_modules() {
  local -n returnModules=$1

  if [ "$allModules" = true ]
  then
    scan::find_modules returnModules
    return
  fi

  if [ "$skipQuestions" = true ]
  then
    # Here we don't add anything, as modules wanted are already set.
    return
  fi

  local foundModules=()
  scan::find_modules foundModules
  for moduleDir in ${foundModules[@]}
  do
    # If it wasn't already present, ask if we want to install it
    if [[ ! " ${returnModules[@]} " =~ " $moduleDir " ]]
    then
      feedback::ask_for_confirmation "Do you want to execute '${moduleDir##*/}'"
      if feedback::answer_is_yes
      then
        returnModules+=("$moduleDir")
      fi
    fi
  done
}
