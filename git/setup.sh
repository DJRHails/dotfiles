#!/usr/bin/env bash

setup_gitconfig () {
  local LOCAL_GIT_CONFIG=git/gitconfig.local
  if ! [ -f $LOCAL_GIT_CONFIG ]
  then
    git_credential='cache'
    if [ "$(uname -s)" == "Darwin" ]
    then
      git_credential='osxkeychain'
    fi

    feedback::ask ' - What is your github author name?'
    git_authorname=$(feedback::get_answer)
    feedback::ask ' - What is your github author email?'
    git_authoremail=$(feedback::get_answer)


    sed -e "s/AUTHORNAME/$git_authorname/g" \
      -e "s/AUTHOREMAIL/$git_authoremail/g" \
      -e "s/GIT_CREDENTIAL_HELPER/$git_credential/g" \
      $LOCAL_GIT_CONFIG.example > $LOCAL_GIT_CONFIG

    log::success 'generated git/gitconfig.local'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
setup_gitconfig
