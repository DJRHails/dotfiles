#!/bin/bash

main() {

    print_in_purple "\n • Restart\n\n"

    ask_for_confirmation "Do you want to restart?"
    printf "\n"

    if answer_is_yes; then
        sudo shutdown -r now &> /dev/null
    fi

 }

. "$DOTFILES_ROOT/script/utils.sh"
 main
