#!/usr/bin/env bash

setup_gitconfig () {
  if ! [ -f git/gitconfig.local.symlink ]
  then
    git_credential='cache'
    if [ "$(uname -s)" == "Darwin" ]
    then
      git_credential='osxkeychain'
    fi

    ask ' - What is your github author name?'
    git_authorname=$(get_answer)
    ask ' - What is your github author email?'
    git_authoremail=$(get_answer)

    sed -e "s/AUTHORNAME/$git_authorname/g" -e "s/AUTHOREMAIL/$git_authoremail/g" -e "s/GIT_CREDENTIAL_HELPER/$git_credential/g" git/gitconfig.local.symlink.example > git/gitconfig.local.symlink

    print_success 'generated git/gitconfig.local.symlink'
  fi
}


. "$DOTFILES_ROOT/script/utils.sh"
setup_gitconfig
