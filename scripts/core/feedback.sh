feedback::ask() {
  log::question "$1 "
  read -r
}

feedback::ask_for_letter() {
  log::question "$1 "
  read -r -n 1
}

feedback::ask_for_confirmation() {
  feedback::ask_for_letter "$1 (y/n)"
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
