#!/usr/bin/env bash

setup_gitconfig () {
  local local_git_config=git/gitconfig.local
  if ! [ -f $local_git_config ]
  then
    git_credential='cache'
    if [ "$(uname -s)" == "Darwin" ]
    then
      git_credential='osxkeychain'
    fi

    prompt::author

    sed -e "s/AUTHORNAME/$GIT_AUTHOR_NAME/g" \
      -e "s/AUTHOREMAIL/$GIT_AUTHOR_EMAIL/g" \
      -e "s/GIT_CREDENTIAL_HELPER/$git_credential/g" \
      $local_git_config.tmpl > $local_git_config

    log::success 'generated git/gitconfig.local'
  else
    log::success 'skipped gitconfig generation as present'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
. "$DOTFILES/git/setup.prompt.sh"
. "$DOTFILES/git/setup.github.sh"
setup_gitconfig
github::setup
