#!/usr/bin/env bash

##? Enforce the 7-day minimum release age in npm and pnpm
##?
##? ~/.npmrc and pnpm's global rc also hold per-machine registry tokens, so
##? neither can itself be a symlink into this repo. npm reads the tracked npmrc
##? (linked to ~/.config/npm/npmrc) as its global config layer once ~/.npmrc
##? carries a one-line `globalconfig=` pointer, and that pointer is all this
##? script writes there. pnpm 10 keeps every global setting in one rc, so its key
##? is written through `pnpm config set -g`; pnpm 12 reads the tracked
##? pnpm-config.yaml instead. bun, uv, pip and cargo come from symlinks.conf.

# shellcheck source=/dev/null
. "$DOTFILES/scripts/core/main.sh"

# True when $1 is at least version $2: with the floor sorting first (or equal),
# the installed version meets it.
release_age::version_at_least() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

release_age_failed=0
npm_policy="$HOME/.config/npm/npmrc"

# npm >= 11.10 for min-release-age. Node 22 LTS bundles npm 10, so a stock
# NodeSource host needs `npm install -g npm` first. The user file outranks the
# global layer, so a copy of the key in ~/.npmrc would shadow the tracked one.
if ! platform::command_exists npm; then
  log::error "npm not installed; min-release-age not set (install the node module first)"
  release_age_failed=1
elif ! release_age::version_at_least "$(npm --version)" 11.10.0; then
  log::error "npm $(npm --version) predates min-release-age (needs 11.10); run: npm install -g npm"
  release_age_failed=1
else
  npm_user="$(npm config get userconfig)"
  if [ "$(npm config get globalconfig 2>/dev/null)" != "$npm_policy" ]; then
    npm config set "globalconfig=$npm_policy" --location=user
    log::result $? "npm globalconfig=$npm_policy (pointer written to $npm_user)"
  fi
  # The first revision of this module wrote the key into ~/.npmrc itself. Take
  # that copy out so the tracked file is the only place the number lives.
  if [ -f "$npm_user" ] && grep -qx 'min-release-age=7' "$npm_user"; then
    npm config delete min-release-age --location=user
    log::result $? "npm: removed the in-place min-release-age an earlier setup wrote to $npm_user"
  fi
  npm_effective="$(npm config get min-release-age 2>/dev/null)"
  if [ "$npm_effective" = 7 ]; then
    log::success "npm min-release-age=7 (from $npm_policy)"
  else
    log::error "npm min-release-age reads '$npm_effective', not 7: is $npm_policy linked, or does $npm_user override it?"
    release_age_failed=1
  fi
fi

# pnpm >= 10.16 for minimum-release-age. pnpm 10 follows npm's pointer too, but
# npm warns on every call about a key it does not know, so pnpm's key cannot
# share that file and is written to pnpm's own rc. pnpm 12 reads the tracked
# config.yaml, finds 10080 already set, and writes nothing.
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
