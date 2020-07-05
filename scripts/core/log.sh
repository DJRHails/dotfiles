log::error() {
    log::red "   [✖] $1 $2\n"
}

log::spinner() {
  local -r FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local -r NUMBER_OR_FRAMES=${#FRAMES}
  local -r INTERVAL=0.08
  local -r PID="$1"
  local -r CMDS="$2"
  local -r MSG="$3"

  local i=0
  local frameText=""

  # Provide more space so that the text hopefully
  # doesn't reach the bottom line of the terminal window.
  #
  # This is a workaround for escape sequences not tracking
  # the buffer position (accounting for scrolling).
  #
  # See also: https://unix.stackexchange.com/a/278888

  printf "\n\n\n"
  tput cuu 3
  tput sc

  while kill -0 "$PID" &>/dev/null; do
    frameText="   [${FRAMES:i++%NUMBER_OR_FRAMES:1}] $MSG"
    printf "%s\n" "$frameText"
    sleep $INTERVAL
    tput rc
  done
}

set_trap() {
  trap -p "$1" | grep "$2" &> /dev/null \
    || trap '$2' "$1"
}

kill_all_subprocesses() {
  local i=""
  for i in $(jobs -p); do
    kill "$i"
    wait "$i" &> /dev/null
  done
}

log::execute() {
  local -r CMDS="$1"
  local -r MSG="${2:-$1}"
  local -r TMP_FILE="$(mktemp /tmp/err_XXXXX)"

  local exitCode=0
  local cmdsPID=""

  set_trap "EXIT" "kill_all_subprocesses"

  eval "$CMDS" &> /dev/null 2> "$TMP_FILE" &
  cmdsPID=$!

  log::spinner "$cmdsPID" "$CMDS" "$MSG"

  wait "$cmdsPID" &> /dev/null
  exitCode=$?

  log::result $exitCode "$MSG"
  if [ $exitCode -ne 0 ]; then
    log::error_stream < "$TMP_FILE"
  fi

  rm -rf "$TMP_FILE"

  return $exitCode
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

log::blue() {
    log::color "$1" 6
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

log::splash() {
  log::blue '     __ _ _                        \n'
  log::blue '    / _(_) | ___  ___              \n'
  log::blue '   | |_| | |/ _ \/ __|             \n'
  log::blue '  _|  _| | |  __/\__ \ from        \n'
  log::blue ' (_)_| |_|_|\___||___/ Daniel Hails\n'
  log::blue "\n$1\n\n"
}

log::success() {
    log::green "   [✔] $1\n"
}

log::warning() {
    log::yellow "   [!] $1\n"
}
