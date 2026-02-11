#!/usr/bin/env bash

setup_gitconfig () {
  local local_git_config=modules/git/gitconfig.local
  if ! [ -f $local_git_config ]
  then
    # git_credential='cache'
    if platform::is_osx
    then
      git_credential='osxkeychain'
    fi

    prompt::author

    sed -e "s/AUTHORNAME/$GIT_AUTHOR_NAME/g" \
      -e "s/AUTHOREMAIL/$GIT_AUTHOR_EMAIL/g" \
      -e "s/GIT_CREDENTIAL_HELPER/$git_credential/g" \
      $local_git_config.tmpl > $local_git_config

    log::success "generated $local_git_config"
  else
    log::success 'skipped gitconfig generation as present'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
. "$DOTFILES/modules/git/setup.prompt.sh"
. "$DOTFILES/modules/git/setup.github.sh"
setup_gitconfig

if [ "$skipQuestions" != true ]; then
  feedback::ask_for_confirmation "Do you want to setup github?"
  if feedback::answer_is_yes
  then
    install::package "Github CLI" "gh"
    install::package "GPG" "gpg"
    github::setup
  fi
fi