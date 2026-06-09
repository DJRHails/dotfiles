#!/usr/bin/env bash

github::install_cli() {
  if platform::command_exists gh; then
    log::success "GitHub CLI"
    return 0
  fi
  if platform::is_osx; then
    install::package "GitHub CLI" "gh"
    return $?
  fi
  # Linux: gh is absent from the default apt repos — add the official one.
  log::info "Adding the GitHub CLI apt repository..."
  platform::sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | platform::sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  platform::sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" \
    | platform::sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  platform::sudo apt update -qq
  install::package "GitHub CLI" "gh"
}

github::add_ssh_configs() {

    printf "%s\n" \
        "Host github.com" \
        "  IdentityFile $1" \
        "  LogLevel ERROR" >> $HOME/.ssh/config

    log::result $? "Add SSH configs"

}

github::copy_public_key_to_clipboard () {

    if platform::command_exists "pbcopy"; then

        pbcopy < "$1"
        log::result $? "Copy public key to clipboard"

    elif platform::command_exists "xclip"; then

        xclip -selection clip < "$1"
        log::result $? "Copy public key to clipboard"

    else
        log::warning "Please copy the public key ($1) to clipboard"
        printf "\n"
        cat "$1"
        printf "\n"
    fi

}

github::generate_ssh_keys() {
    prompt::author_email

    ssh-keygen -t rsa -b 4096 -C "$GIT_AUTHOR_EMAIL" -f "$1"

    log::result $? "Generate SSH keys"
}

github::generate_gpg_keys() {
  local genkeyFile passphrase

  prompt::author
  feedback::ask ' - What is your gpg passphrase?'
  passphrase=$(feedback::get_answer)

  # Build the batch file in-shell (printf is a builtin) so the passphrase
  # never appears in any process argv; 600 temp file, removed on return.
  genkeyFile="$(mktemp)"
  chmod 600 "$genkeyFile"
  trap 'rm -f "$genkeyFile"; trap - RETURN' RETURN

  printf '%s\n' \
    'Key-Type: 1' \
    'Key-Length: 4096' \
    'Subkey-Type: 1' \
    'Subkey-Length: 4096' \
    "Name-Real: ${GIT_AUTHOR_NAME}" \
    "Name-Email: ${GIT_AUTHOR_EMAIL}" \
    'Name-Comment: git-auto' \
    'Expire-Date: 0' \
    "Passphrase: ${passphrase}" > "$genkeyFile"

  gpg --gen-key --batch "$genkeyFile" > /dev/null
  shred -u "$genkeyFile"
}

github::open_keys_page() {

    declare -r GITHUB_KEYS_URL="https://github.com/settings/keys"

    platform::open "$GITHUB_KEYS_URL"
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
  gpgKeyId="$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null \
    | grep git-auto -B 2 \
    | grep sec \
    | perl -nle 'print $& while m{(?<=/)[A-Z0-9]{16}}g')"
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
    github::get_gpg_key_id $gpgKeyId
    gpg --armor --export ${gpgKeyId} > ${gpgKeyFileName}
    github::copy_public_key_to_clipboard "${gpgKeyFileName}"
    github::open_keys_page
    feedback::ask_for_confirmation "Have you copied the PGP Key?"

    if ! feedback::answer_is_yes
    then
        gpg --delete-secret-key ${gpgKeyId}
        gpg --delete-key ${gpgKeyId}
    else
      github::update_local_with_gpg
    fi
}

github::update_local_with_gpg() {
  local local_git_config=modules/git/gitconfig.local
  git config --file "$local_git_config" user.signingkey "$gpgKeyId"
  git config --file "$local_git_config" commit.gpgsign true
}

github::test_ssh_connection() {
    local -r maxAttempts=12
    local attempt exitCode

    for ((attempt = 1; attempt <= maxAttempts; attempt++)); do
        ssh -T git@github.com &> /dev/null
        exitCode=$?

        # GitHub never grants a shell: exit 1 means the key authenticated.
        if [ "$exitCode" -eq 1 ]; then
            log::success "GitHub SSH connection authorized"
            return 0
        fi

        if [ "$exitCode" -eq 255 ]; then
            log::warning "Attempt $attempt/$maxAttempts: key not yet authorized — paste the public key at https://github.com/settings/keys"
        else
            log::warning "Attempt $attempt/$maxAttempts: ssh to GitHub failed (exit $exitCode)"
        fi

        [ "$attempt" -lt "$maxAttempts" ] && sleep 5
    done

    log::error "GitHub SSH connection not authorized after $maxAttempts attempts"
    return 1
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
  log::execute "github::get_gpg_key_id" "get GPG key"
  local exitCode=$?

  if [[ $exitCode -eq 0 ]]; then
    github::get_gpg_key_id
  fi
  if [[ $exitCode -eq 0 && -z $gpgKeyId ]]
  then
    feedback::ask_for_confirmation "Do you want to setup GPG signing?"

    if feedback::answer_is_yes; then
      github::set_gpg_key
    fi

    log::result $? "set up GitHub GPG key"
  elif [ $exitCode -eq 0 ]
  then
    log::success "skipped GitHub GPG key already present ($gpgKeyId)"
  else
    log::error "GPG key lookup failed (exit $exitCode)"
  fi
}
