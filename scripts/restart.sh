#!/bin/bash

main() {
    log::header "Restart\n"

    if [ "$skipQuestions" = true ]; then
        log::success "skipped restart (non-interactive mode)"
        return
    fi

    feedback::ask_for_confirmation "Do you want to restart?"
    printf "\n"

    if feedback::answer_is_yes; then
        sudo shutdown -r now &> /dev/null
    fi

 }

. "$DOTFILES/scripts/core/main.sh"
 main
