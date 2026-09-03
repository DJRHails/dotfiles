#!/usr/bin/env bash
# Behavior suite for modules/ci-runners/git-credential-public-read.
# Self-contained: `bash tests/git-credential-public-read.test.sh`. Exits non-zero on failure.
#
# The helper's whole value is in its fail direction: with no token on disk it must be
# silent, so a runner without one keeps today's behaviour exactly; with one, it must
# answer only `get`, and only for github.com. The last check drives it through git's
# own credential machinery (`git credential fill`), with the config key provision.sh
# writes, so the shape git actually invokes is what is pinned — not just the script.
set -u

unset "${!GIT_@}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$(cd "$script_dir/.." && pwd)/modules/ci-runners/git-credential-public-read"

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf -- "$work"' EXIT

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

github_desc=$'protocol=https\nhost=github.com\n'
run_helper() { # <action> <description> -> stdout, with the exit code on the last line
  local out
  out="$(printf '%s' "$2" | ACTIONS_RUNNER_GITHUB_TOKEN_FILE="$work/token" bash "$helper" "$1" 2>&1)"
  printf '%s\nrc=%s' "$out" "$?"
}

check "no token file: get is silent and exits 0" $'\nrc=0' "$(run_helper get "$github_desc")"

: >"$work/token"
check "empty token file: get is silent and exits 0" $'\nrc=0' "$(run_helper get "$github_desc")"

printf '  ghp_example_token  \n\nsecond line never read\n' >"$work/token"
check "get answers github.com with the trimmed first line" \
  $'username=x-access-token\npassword=ghp_example_token\nrc=0' "$(run_helper get "$github_desc")"

check "get ignores another host" $'\nrc=0' "$(run_helper get $'protocol=https\nhost=gitlab.com\n')"
check "get ignores a description with no host" $'\nrc=0' "$(run_helper get $'protocol=https\n')"
check "store is a no-op" $'\nrc=0' "$(run_helper store "$github_desc")"
check "erase is a no-op" $'\nrc=0' "$(run_helper erase "$github_desc")"
check "no action is a no-op" $'\nrc=0' "$(run_helper '' "$github_desc")"

# Through git itself, with the key provision.sh writes. `credential fill` runs the
# configured helpers for the description on stdin and prints the filled result.
# The machine's own git config is shut out (GIT_CONFIG_GLOBAL/NOSYSTEM), and git
# runs from the scratch dir rather than this checkout, whose own .git/config may
# name a helper too (a gantry clone does): helpers run in config order and the
# first answer wins, so any other helper in scope answers in this one's place.
# Prompts are off, so a missing answer fails fast instead of hanging on a terminal.
git_fill() { # <description> -> filled credential, or git's error
  printf '%s' "$1" |
    ACTIONS_RUNNER_GITHUB_TOKEN_FILE="$work/token" GIT_TERMINAL_PROMPT=0 \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      git -C "$work" -c "credential.https://github.com.helper=$helper" credential fill 2>&1 || true
}

# A stray answer here is some other helper's real credential; report it redacted.
redact_password() { sed 's/^password=.*/password=<redacted>/'; }

filled="$(git_fill "$github_desc")"
case "$filled" in
*$'username=x-access-token\npassword=ghp_example_token'*)
  check "git credential fill takes the helper's answer for github.com" "answered" "answered"
  ;;
*)
  check "git credential fill takes the helper's answer for github.com" "answered" \
    "$(printf '%s' "$filled" | redact_password)"
  ;;
esac

filled_other="$(git_fill $'protocol=https\nhost=gitlab.com\n')"
case "$filled_other" in
*password=*) check "git asks nothing of the helper for another host" "no password" "password leaked" ;;
*) check "git asks nothing of the helper for another host" "no password" "no password" ;;
esac

exit "$fails"
