#!/usr/bin/env bash
# Mirror this host's Claude Code session stores to palst, one `palst sync --watch` per store.
# Run by the launchd agent / systemd user unit from this module's install scripts; exits
# non-zero when any watcher dies so the supervisor restarts the whole set.
set -euo pipefail

((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1))) || {
  echo "palst-sync: needs bash >= 5.1 for 'wait -n <pids>' (got $BASH_VERSION)" >&2
  exit 1
}

PALST="${PALST_BIN:-$HOME/.local/bin/palst}"
INSTALL_HINT="uv tool install --force <palst source>"
# Older clients route a subagent transcript by its parent's session id and PUT it over the
# parent's upload, so a watcher on a Claude store needs at least this.
MIN_VERSION="0.74.2"
CONCURRENCY="${PALST_SYNC_CONCURRENCY:-4}"
STORES=("$HOME/.claude/projects" "$HOME/.claude-ant/projects")

die() {
  echo "palst-sync: $*" >&2
  exit 1
}

[[ -x "$PALST" ]] || die "no palst CLI at $PALST; run: $INSTALL_HINT"

installed="$(uv tool list 2>/dev/null | awk '$1 == "palst" { sub(/^v/, "", $2); print $2 }')"
[[ -n "$installed" ]] || die "cannot read the palst version from 'uv tool list'"
lowest="$(printf '%s\n%s\n' "$MIN_VERSION" "$installed" | sort -V | head -n1)"
[[ "$lowest" == "$MIN_VERSION" ]] ||
  die "palst $installed is older than $MIN_VERSION; run: $INSTALL_HINT"

"$PALST" whoami >/dev/null || die "palst is not logged in; run: palst login"

pids=()
for store in "${STORES[@]}"; do
  [[ -d "$store" ]] || continue
  echo "palst-sync: watching $store"
  "$PALST" sync "$store" --watch --concurrency "$CONCURRENCY" &
  pids+=("$!")
done
((${#pids[@]} > 0)) || die "no Claude session store found (looked in: ${STORES[*]})"

trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
status=0
wait -n "${pids[@]}" || status=$?
die "a watcher exited (status $status); stopping the rest so the supervisor restarts the set"
