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

    sed -e "s/AUTHORNAME/$GIT_AUTHOR_NAME/g" \
      -e "s/AUTHOREMAIL/$GIT_AUTHOR_EMAIL/g" \
      -e "s/GIT_CREDENTIAL_HELPER/$git_credential/g" \
      $local_git_config.tmpl > $local_git_config

    log::success 'generated git/gitconfig.local'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
setup_gitconfig
