#!/usr/bin/env zsh
# Behavior suite for the sfw wrappers (modules/sfw/aliases.zsh): fetching
# subcommands route through sfw, everything else reaches the real tool.
# Self-contained: `zsh -f tests/sfw-aliases.test.zsh`. Exits non-zero on failure.
set -u

script_dir="${0:A:h}"
aliases_zsh="$script_dir/../modules/sfw/aliases.zsh"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
path=("$work/bin" $path)

# The sfw stub prints a marker and stops (never spawns the wrapped manager);
# the fake managers print a REAL marker — each call's routing is observable.
printf '#!/bin/sh\necho "SFW $@"\n' > "$work/bin/sfw"
for tool in npm pnpm yarn pip pip3 uv cargo npx uvx; do
  printf '#!/bin/sh\necho "REAL %s $@"\n' "$tool" > "$work/bin/$tool"
done
chmod +x "$work/bin/"*

source "$aliases_zsh"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}

check "npm install routes via sfw" \
  "SFW npm install left-pad" "$(npm install left-pad)"
check "npm isntall (typo alias) routes via sfw" \
  "SFW npm isntall left-pad" "$(npm isntall left-pad)"
check "npm x (exec alias) routes via sfw" \
  "SFW npm x cowsay" "$(npm x cowsay)"
check "npm run stays unwrapped" \
  "REAL npm run build" "$(npm run build)"
check "leading flag is skipped when matching the verb" \
  "SFW npm --prefix=. install" "$(npm --prefix=. install)"
check "pnpm upgrade (update alias) routes via sfw" \
  "SFW pnpm upgrade" "$(pnpm upgrade)"
check "pnpm create routes via sfw" \
  "SFW pnpm create vite" "$(pnpm create vite)"
check "pnpm run stays unwrapped" \
  "REAL pnpm run dev" "$(pnpm run dev)"
check "bare yarn is an install, routes via sfw" \
  "SFW yarn" "$(yarn)"
check "yarn global add routes via sfw" \
  "SFW yarn global add left-pad" "$(yarn global add left-pad)"
check "yarn run stays unwrapped" \
  "REAL yarn run dev" "$(yarn run dev)"
check "pip install routes via sfw" \
  "SFW pip install requests" "$(pip install requests)"
check "pip3 install routes via sfw" \
  "SFW pip3 install requests" "$(pip3 install requests)"
check "pip freeze stays unwrapped" \
  "REAL pip freeze" "$(pip freeze)"
check "uv add routes via sfw" \
  "SFW uv add rich" "$(uv add rich)"
check "uv run stays unwrapped" \
  "REAL uv run app.py" "$(uv run app.py)"
check "cargo +toolchain install routes via sfw" \
  "SFW cargo +nightly install ripgrep" "$(cargo +nightly install ripgrep)"
check "cargo build stays unwrapped" \
  "REAL cargo build" "$(cargo build)"
check "npx is always wrapped" \
  "SFW npx cowsay" "$(npx cowsay)"
check "uvx is always wrapped" \
  "SFW uvx ruff" "$(uvx ruff)"

if (( fails )); then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
print '\nall checks passed'
