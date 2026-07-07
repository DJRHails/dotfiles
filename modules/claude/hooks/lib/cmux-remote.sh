#!/usr/bin/env bash
# Shared cmux transport: talk to the cmux app socket from either the cmux UI host
# (the mac) or a durable/mosh remote (e.g. bonbon, which has no cmux installed).
# Sourced by cmux-fork-session (the rename hook is now sync_cmux_tab.py, python).
#
# Do NOT force CMUX_SOCKET_PATH: cmux auto-discovers its own socket, and the path
# moved from "~/Library/Application Support/cmux" to "~/.local/state/cmux" in a
# recent build — so any hardcoded value goes stale ("Socket not found"). We let
# the app find it (and inherit the env value cmux already injected, when present).

# macOS host running cmux.app — resolved through the ssh::ui_host convention
# (modules/ssh/lib.zsh: first CODE_UI_HOSTS entry, default trifle) so the UI
# host is configured in one place. The lib is zsh (its array can't be exported
# to this bash hook), so ask a zsh for the answer; hard fallback stays trifle.
if [[ -z "${CMUX_APP_HOST:-}" ]]; then
  _ssh_lib="$(dirname "${BASH_SOURCE[0]}")/../../../ssh/lib.zsh"
  CMUX_APP_HOST=$(zsh -c "source '$_ssh_lib' 2>/dev/null && ssh::ui_host" 2>/dev/null || true)
  CMUX_APP_HOST="${CMUX_APP_HOST:-trifle}"
fi
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
