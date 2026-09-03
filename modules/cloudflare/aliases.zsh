#!/bin/bash
#
# Cloudflare's unified `cf` CLI, authenticated with a long-lived user API token.
#
# The token lives in modules/cloudflare/.env (gitignored, mode 600), one line:
#   CLOUDFLARE_API_TOKEN=<token>
# `cf` reads CLOUDFLARE_API_TOKEN before any OAuth profile, so the wrapper
# sources the file in a subshell and the token is scoped to that one cf call
# rather than exported into every shell (the claude::ant pattern). Without the
# file, `cf` behaves as installed: `cf auth login` OAuth profiles, which expire.
#
# The token itself is minted in the dashboard (My Profile -> API Tokens ->
# Create Custom Token, no TTL); its permissions can be widened there later
# without changing the value. Rotate by replacing the line in .env.
_cloudflare_aliases_dir="${${(%):-%x}:A:h}"

cf() {
  local env_file="${_cloudflare_aliases_dir}/.env"
  if [[ -f $env_file ]]; then
    (
      set -a
      source "$env_file"
      set +a
      command cf "$@"
    )
  else
    command cf "$@"
  fi
}
