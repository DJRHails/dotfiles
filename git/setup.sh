#!/usr/bin/env bash

setup_gitconfig () {
  if ! [ -f git/gitconfig.local.symlink ]
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
      git/gitconfig.local.example > git/gitconfig.local

    log::success 'generated git/gitconfig.local'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
setup_gitconfig
