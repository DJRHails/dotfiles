#!/usr/bin/env bash
# Shared cmux transport: talk to the cmux app socket from either the cmux UI host
# (the mac) or a durable/mosh remote (e.g. bonbon, which has no cmux installed).
# Sourced by sync-cmux-tab.sh (the rename hook) and cmux-fork-session.
#
# Do NOT force CMUX_SOCKET_PATH: cmux auto-discovers its own socket, and the path
# moved from "~/Library/Application Support/cmux" to "~/.local/state/cmux" in a
# recent build — so any hardcoded value goes stale ("Socket not found"). We let
# the app find it (and inherit the env value cmux already injected, when present).

CMUX_APP_HOST="${CMUX_APP_HOST:-trifle}" # macOS host running cmux.app
CMUX_APP_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"

# True on the cmux UI host: the app binary is installed here.
cmux_is_local() { [ -x "$CMUX_APP_BIN" ]; }

# run_cmux <args...> — run a cmux command against the app socket. Locally, exec the
# app binary (it auto-discovers the socket). Remotely, ssh to the app host and run
# *its* cmux there, args base64-encoded per-arg so the JSON survives ssh re-quoting.
run_cmux() {
  if cmux_is_local; then
    "$CMUX_APP_BIN" "$@"
  else
    local enc="" a
    for a in "$@"; do enc+=" $(printf %s "$a" | base64 | tr -d '\n')"; done
    # -n: never read the caller's stdin (a hook's stdin / a script body would
    # otherwise be consumed by ssh). $enc is built client-side on purpose (base64
    # tokens, decoded remotely) — SC2029 is the design.
    # shellcheck disable=SC2029
    ssh -n "$CMUX_APP_HOST" "C=$CMUX_APP_BIN
      aa=(); for t in$enc; do aa+=(\"\$(printf %s \"\$t\" | openssl base64 -d -A)\"); done
      exec \"\$C\" \"\${aa[@]}\""
  fi
}
