feedback::ask() {
    log::question "$1 "
    read -r
}

feedback::ask_for_confirmation() {
    log::question "$1 (y/n) "
    read -r -n 1
    printf "\n"
}

feedback::get_answer() {
    printf "%s" "$REPLY"
}

feedback::answer_is_yes() {
    [[ "$REPLY" =~ ^[Yy]$ ]] \
        && return 0 \
        || return 1
}
