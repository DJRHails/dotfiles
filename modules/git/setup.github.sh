#!/usr/bin/env bash

github::add_ssh_configs() {

    printf "%s\n" \
        "Host github.com" \
        "  IdentityFile $1" \
        "  LogLevel ERROR" >> $HOME/.ssh/config

    log::result $? "Add SSH configs"

}

github::copy_public_key_to_clipboard () {

    if cmd_exists "pbcopy"; then

        pbcopy < "$1"
        log::result $? "Copy public key to clipboard"

    elif cmd_exists "xclip"; then

        xclip -selection clip < "$1"
        log::result $? "Copy public key to clipboard"

    else
        log::warning "Please copy the public key ($1) to clipboard"
    fi

}

github::generate_ssh_keys() {
    prompt::author_email

    ssh-keygen -t rsa -b 4096 -C "$GIT_AUTHOR_EMAIL" -f "$1"

    log::result $? "Generate SSH keys"
}

github::generate_gpg_keys() {
  local local_genkey_definition=git/genkey

  prompt::author
  feedback::ask ' - What is your gpg passphrase?'
  passphrase=$(feedback::get_answer)

  sed -e "s/AUTHORNAME/${GIT_AUTHOR_NAME}/g" \
    -e "s/AUTHOREMAIL/${GIT_AUTHOR_EMAIL}/g" \
    -e "s/PASSPHRASE/${passphrase}/g" \
    $local_genkey_definition.tmpl > $local_genkey_definition

  gpg --gen-key --batch $local_genkey_definition > /dev/null
  shred -u $local_genkey_definition
}

github::open_keys_page() {

    declare -r GITHUB_KEYS_URL="https://github.com/settings/keys"

    # The order of the following checks matters
    # as on Ubuntu there is also a utility called `open`.

    if cmd_exists "xdg-open"; then
        xdg-open "$GITHUB_KEYS_URL"
    elif cmd_exists "open"; then
        open "$GITHUB_KEYS_URL"
    else
        log::warning "Please add the public key to GitHub ($GITHUB_KEYS_URL)"
    fi

}

github::set_ssh_key() {

    local sshKeyFileName="$HOME/.ssh/github"

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # If there is already a file with that
    # name, generate another, unique, file name.

    if [ -f "$sshKeyFileName" ]; then
        sshKeyFileName="$(mktemp -u "$HOME/.ssh/github_XXXXX")"
    fi

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    github::generate_ssh_keys "$sshKeyFileName"
    github::add_ssh_configs "$sshKeyFileName"
    github::copy_public_key_to_clipboard "${sshKeyFileName}.pub"
    github::open_keys_page
    github::test_ssh_connection \
        && rm "${sshKeyFileName}.pub"

}

github::get_gpg_key_id() {
  gpg_key_id="$(gpg --list-secret-keys --keyid-format LONG \
    | grep git-auto -B 2 \
    | grep sec \
    | grep -o -P '(?<=/)[A-Z0-9]{16}')"
}

github::set_gpg_key() {
  mkdir -p "$HOME/.gpg"
  local gpgKeyFileName="$HOME/.gpg/github"

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # If there is already a file with that
  # name, generate another, unique, file name.

  if [ -f "$gpgKeyFileName" ]; then
      gpgKeyFileName="$(mktemp -u "$HOME/.gpg/github_XXXXX")"
  fi

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    github::generate_gpg_keys
    github::get_gpg_key_id
    gpg --armor --export ${gpg_key_id} > ${gpgKeyFileName}
    github::copy_public_key_to_clipboard "${gpgKeyFileName}"
    github::open_keys_page
    feedback::ask_for_confirmation "Have you copied the PGP Key?"

    if ! feedback::answer_is_yes
    then
        gpg --delete-secret-key ${gpg_key_id}
        gpg --delete-key ${gpg_key_id}
    else
      github::update_local_with_gpg
    fi
}

github::update_local_with_gpg() {
  local local_git_config=git/gitconfig.local
  git config --file $local_git_config user.signingkey $gpg_key_id
}

github::test_ssh_connection() {
    while true; do
        ssh -T git@github.com &> /dev/null
        [ $? -eq 1 ] && break

        sleep 5
    done
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

github::setup() {
  # Frustratingly ssh -T returns success in stderr, so I duplicate it
  # with tee into stdout and stderr, then grep for success in stdout
  log::execute "ssh -T git@github.com 2> >(tee >(cat >&2)) | grep success" \
    "Testing ssh credentials"

  if [ $? -ne 0 ]; then
      github::set_ssh_key
      log::result $? "set up GitHub SSH key"
  fi

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  log::execute github::get_gpg_key_id "Get GPG key"
  if [[ $? -eq 0 && -z $gpg_key_id ]]
  then
    feedback::ask_for_confirmation "Do you want to setup GPG signing?"

    if feedback::answer_is_yes; then
      github::set_gpg_key
    fi

    log::result $? "set up GitHub GPG key"
  elif [ $? -eq 0 ]
  then
    log::success "skipped GitHub GPG key already present ($gpg_key_id)"
  fi
}
