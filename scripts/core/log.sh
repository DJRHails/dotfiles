log::error() {
    log::red "   [✖] $1 $2\n"
}

log::error_stream() {
    while read -r line; do
        log::error "↳ ERROR: $line"
    done
}

log::bold() {
  printf "%b" \
      "$(tput smso 2> /dev/null)" \
      "$1" \
      "$(tput rmso 2> /dev/null)"
}

log::color() {
    printf "%b" \
        "$(tput setaf "$2" 2> /dev/null)" \
        "$1" \
        "$(tput sgr0 2> /dev/null)"
}

log::green() {
    log::color "$1" 2
}

log::purple() {
    log::color "$1" 5
}

log::red() {
    log::color "$1" 1
}

log::yellow() {
    log::color "$1" 3
}

log::question() {
    log::yellow "   [?] $1"
}

log::result() {

    if [ "$1" -eq 0 ]; then
        log::success "$2"
    else
        log::error "$2"
    fi

    return "$1"

}

log::header() {
    log::purple "\n • $1\n"
}

log::subheader() {
    log::purple "\n   $1\n"
}

log::success() {
    log::green "   [✔] $1\n"
}

log::warning() {
    log::yellow "   [!] $1\n"
}
