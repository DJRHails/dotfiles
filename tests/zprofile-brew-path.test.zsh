#!/usr/bin/env zsh
# Behavior suite for the Homebrew PATH handling in modules/zsh/zprofile.
# Self-contained: `zsh -f tests/zprofile-brew-path.test.zsh`. Exits non-zero on failure.
#
# A nested login shell inherits HOMEBREW_PREFIX, and on macOS /etc/zprofile's
# path_helper has re-sorted the inherited PATH with the system directories first
# by the time ~/.zprofile runs. These cases start from that demoted PATH.
set -u

script_dir="${0:A:h}"
zprofile="$script_dir/../modules/zsh/zprofile"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
brew="$work/brew"
mkdir -p "$brew/bin" "$brew/sbin"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}

# Source zprofile in a fresh non-rc shell with the given PATH and an inherited
# HOMEBREW_PREFIX, and print the resulting PATH.
run() { HOMEBREW_PREFIX="$brew" PATH="$1" zsh -f -c "source ${(q)zprofile}; print -r -- \$PATH" }

# brew demoted behind the system dirs: it comes back to the front, once
check demoted "$brew/bin:$brew/sbin:/usr/bin:/bin:/extra" \
  "$(run "/usr/bin:/bin:$brew/bin:/extra:$brew/sbin")"

# brew missing from the inherited PATH altogether: it is added at the front
check missing "$brew/bin:$brew/sbin:/usr/bin:/bin" \
  "$(run "/usr/bin:/bin")"

# brew already in front: nothing moves, nothing is duplicated
check already-first "$brew/bin:$brew/sbin:/usr/bin:/bin" \
  "$(run "$brew/bin:$brew/sbin:/usr/bin:/bin")"

# the point of it all: a tool installed by brew wins over the system copy
print '#!/bin/sh\necho brew' > "$brew/bin/bash"
chmod +x "$brew/bin/bash"
check brew-bash-wins "$brew/bin/bash" \
  "$(HOMEBREW_PREFIX="$brew" PATH="/usr/bin:/bin:$brew/bin" \
    zsh -f -c "source ${(q)zprofile}; print -r -- \$commands[bash]")"

(( fails == 0 )) || exit 1
