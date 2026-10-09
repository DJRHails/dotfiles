#!/usr/bin/env bash

##? Enforce the 7-day minimum release age in npm and pnpm
##?
##? ~/.npmrc and pnpm's global rc already hold per-machine registry tokens, so
##? neither can be a symlink into this repo. Each tool's own `config set`
##? rewrites its file in place and keeps every other line. bun, uv, pip and
##? cargo have no such file and come from symlinks.conf.

# shellcheck source=/dev/null
. "$DOTFILES/scripts/core/main.sh"

# True when $1 is at least version $2: with the floor sorting first (or equal),
# the installed version meets it.
release_age::version_at_least() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

release_age_failed=0

# npm: min-release-age, in days, npm >= 11.10. Node 22 LTS bundles npm 10, so
# a stock NodeSource host needs `npm install -g npm` before this can apply.
if ! platform::command_exists npm; then
  log::error "npm not installed; min-release-age not set (install the node module first)"
  release_age_failed=1
elif ! release_age::version_at_least "$(npm --version)" 11.10.0; then
  log::error "npm $(npm --version) predates min-release-age (needs 11.10); run: npm install -g npm"
  release_age_failed=1
elif [ "$(npm config get min-release-age 2>/dev/null)" = 7 ]; then
  log::success "npm min-release-age=7"
else
  npm config set min-release-age=7 --location=user
  log::result $? "npm min-release-age=7 -> $(npm config get userconfig)"
fi

# pnpm: minimum-release-age, in minutes, pnpm >= 10.16. `config set -g` writes
# the global rc (pnpm 10) or config.yaml (pnpm 12) and reads back from either.
if ! platform::command_exists pnpm; then
  log::error "pnpm not installed; minimum-release-age not set (install the node module first)"
  release_age_failed=1
elif ! release_age::version_at_least "$(pnpm --version)" 10.16.0; then
  log::error "pnpm $(pnpm --version) predates minimum-release-age (needs 10.16); run: corepack use pnpm@latest"
  release_age_failed=1
elif [ "$(pnpm config get minimum-release-age 2>/dev/null)" = 10080 ]; then
  log::success "pnpm minimum-release-age=10080"
else
  pnpm config set -g minimum-release-age 10080
  log::result $? "pnpm minimum-release-age=10080 -> $(pnpm config get globalconfig)"
fi

[ "$release_age_failed" -eq 0 ] || return 1
