#!/usr/bin/env bash
# Install (or rotate) the public-read-only GitHub token that taffy's CI runners
# answer GitHub's anonymous-throttle challenge with. Run ON taffy; needs
# passwordless sudo. No runner restart — git reads the file on the next challenge.
#
#     ./set-github-token.sh              # prompts for the token (no echo)
#     ./set-github-token.sh < token.txt  # or reads it from stdin
#
# Mint the token at https://github.com/settings/personal-access-tokens/new as a
# FINE-GRAINED token: resource owner DJRHails, repository access "Public
# repositories (read-only)", and NO account or repository permissions. That is
# the whole point of it: every CI job on this host can read the file it lands
# in, so the token must be worth nothing — it reads what anyone can read, and it
# lifts the anonymous throttle only because GitHub rate-limits authenticated git
# per token rather than per IP. The checks below refuse anything broader.
set -euo pipefail

TOKEN_FILE=/etc/actions-runner/github-public-read-token
RUNNER_USER=actions
PROBE_PUBLIC=DJRHails/graphs      # public: the token must read it on the git endpoint
PROBE_PRIVATE=DJRHails/touchstone # private: the token must NOT see it at all

die() {
  echo "error: $*" >&2
  exit 1
}

sudo -n true 2>/dev/null || die "passwordless sudo required (writes ${TOKEN_FILE})"
id -u "$RUNNER_USER" >/dev/null 2>&1 || die "no '${RUNNER_USER}' user — provision runners first"

if [ -t 0 ]; then
  read -r -s -p "GitHub fine-grained token (public repositories, read-only): " token
  echo
else
  read -r token
fi
token="$(printf '%s' "$token" | tr -d '[:space:]')"
[ -n "$token" ] || die "empty token"

# The token never rides argv (ps shows argv to every user on the host): curl reads
# it from a netrc file, git from env-scoped config.
netrc="$(mktemp)"
trap 'rm -f "$netrc"' EXIT
chmod 600 "$netrc"
printf 'machine api.github.com login x-access-token password %s\n' "$token" >"$netrc"

api() { curl -sS --netrc-file "$netrc" "$@"; }

# Classic tokens report their scopes in a response header; a fine-grained one
# carries none. Refuse a classic token outright: even scope-less it is the
# account's OAuth grant, and the scoped ones are exactly what must not sit here.
headers="$(api -o /dev/null -D - https://api.github.com/user)"
status="$(printf '%s' "$headers" | head -n 1 | awk '{print $2}')"
[ "$status" = 200 ] || die "GitHub rejected the token (HTTP ${status})"
if printf '%s' "$headers" | grep -qi '^x-oauth-scopes:'; then
  die "that is a classic token ($(printf '%s' "$headers" | grep -i '^x-oauth-scopes:' | tr -d '\r')) — mint a fine-grained one"
fi
expiry="$(printf '%s' "$headers" | grep -i '^github-authentication-token-expiration:' | cut -d' ' -f2- | tr -d '\r' || true)"

# Least privilege, proved rather than assumed: a private repo must read as absent.
priv="$(api -o /dev/null -w '%{http_code}' "https://api.github.com/repos/${PROBE_PRIVATE}")"
[ "$priv" = 404 ] ||
  die "the token can see ${PROBE_PRIVATE} (HTTP ${priv}) — it has private-repo access; mint one with 'Public repositories (read-only)' only"

# And the git endpoint itself must accept it, sent up front: a bad or unsupported
# Authorization header is refused there even on a public repo, so this cannot
# pass by accident of the repo being public.
basic="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0='http.https://github.com/.extraheader' \
  GIT_CONFIG_VALUE_0="Authorization: Basic ${basic}" \
  git ls-remote --heads "https://github.com/${PROBE_PUBLIC}.git" >/dev/null 2>&1 ||
  die "GitHub's git endpoint refused the token on ${PROBE_PUBLIC}"

sudo install -d -m 0750 -o root -g "$RUNNER_USER" "$(dirname "$TOKEN_FILE")"
sudo install -m 0640 -o root -g "$RUNNER_USER" /dev/null "$TOKEN_FILE"
printf '%s\n' "$token" | sudo tee "$TOKEN_FILE" >/dev/null
echo "installed ${TOKEN_FILE} (root:${RUNNER_USER} 0640)${expiry:+; expires ${expiry}}"
echo "runners answer their next github.com challenge with it — no restart needed"
