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
      $local_git_config.tmpl > $local_git_config

    # Only record a credential helper when one was actually chosen. An empty
    # `helper =` line would reset git's accumulated helper list (gitconfig.local
    # is included last), wiping e.g. gh's helper on Linux where git_credential
    # is unset.
    if [ -n "${git_credential:-}" ]
    then
      git config --file "$local_git_config" credential.helper "$git_credential"
    fi

    log::success "generated $local_git_config"
  else
    log::success 'skipped gitconfig generation as present'
  fi
}


. "$DOTFILES/scripts/core/main.sh"
. "$DOTFILES/modules/git/setup.prompt.sh"
. "$DOTFILES/modules/git/setup.github.sh"
setup_gitconfig

install::package "Git LFS" "git-lfs"
install::package "Transcrypt" "transcrypt"
github::install_cli

if [ "$skipQuestions" != true ]; then
  feedback::ask_for_confirmation "Do you want to setup github?"
  if feedback::answer_is_yes
  then
    install::package "GPG" "gpg"
    github::setup
  fi
fi