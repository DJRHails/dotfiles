#!/usr/bin/env bash

github::add_ssh_configs() {

    printf "%s\n" \
        "Host github.com" \
        "  IdentityFile $1" \
        "  LogLevel ERROR" >> ~/.ssh/config

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


github::test_ssh_connection() {
    while true; do
        ssh -T git@github.com &> /dev/null
        [ $? -eq 1 ] && break

        sleep 5
    done
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

github::setup() {

    log::purple "     - Testing ssh credentials...\n"
    ssh -T git@github.com &> /dev/null

    if [ $? -ne 1 ]; then
        github::set_ssh_key
    fi

    log::result $? "set up GitHub SSH key"

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

}
