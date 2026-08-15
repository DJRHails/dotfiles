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
# The binary has moved between builds — Contents/Resources/app/bin/cmux, then
# Contents/Resources/bin/cmux, now Contents/MacOS/cmux — and a stale hardcode fails in the
# worst way: cmux_is_local() returns false ON the UI host, so it ssh'es to itself with a path
# that does not exist. Probe a candidate list instead, newest layout first, and let $PATH win
# if the user has cmux installed there.
CMUX_APP_BIN_CANDIDATES=(
  "${CMUX_APP_BIN:-}"
  "/Applications/cmux.app/Contents/MacOS/cmux"
  "/Applications/cmux.app/Contents/Resources/bin/cmux"
  "/Applications/cmux.app/Contents/Resources/app/bin/cmux"
)

# First candidate that exists locally, else empty.
_cmux_local_bin() {
  local c
  for c in "${CMUX_APP_BIN_CANDIDATES[@]}"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  command -v cmux 2>/dev/null || true
}

# True on the cmux UI host: some cmux binary is installed here.
cmux_is_local() { [ -n "$(_cmux_local_bin)" ]; }

# run_cmux <args...> — run a cmux command against the app socket. Locally, exec the
# app binary (it auto-discovers the socket). Remotely, ssh to the app host and run
# *its* cmux there, args base64-encoded per-arg so the JSON survives ssh re-quoting.
run_cmux() {
  local bin
  bin="$(_cmux_local_bin)"
  if [ -n "$bin" ]; then
    "$bin" "$@"
  else
    local enc="" a
    for a in "$@"; do enc+=" $(printf %s "$a" | base64 | tr -d '\n')"; done
    # The remote resolves the binary itself: our local candidate list is about THIS host, and
    # the app path differs between builds, so shipping one path guarantees breakage the next
    # time it moves. Probe the same candidates over there and fail loudly if none exist.
    local remote_probe
    remote_probe=$(printf '%s\n' "${CMUX_APP_BIN_CANDIDATES[@]}" | grep -v '^$' | tr '\n' ' ')
    # -n: never read the caller's stdin (a hook's stdin / a script body would
    # otherwise be consumed by ssh). $enc is built client-side on purpose (base64
    # tokens, decoded remotely) — SC2029 is the design.
    # shellcheck disable=SC2029
    ssh -n "$CMUX_APP_HOST" "C=''
      for c in $remote_probe; do [ -x \"\$c\" ] && { C=\"\$c\"; break; }; done
      [ -n \"\$C\" ] || C=\$(command -v cmux 2>/dev/null)
      [ -n \"\$C\" ] || { echo 'cmux-remote: no cmux binary on $CMUX_APP_HOST (checked: $remote_probe)' >&2; exit 127; }
      aa=(); for t in$enc; do aa+=(\"\$(printf %s \"\$t\" | openssl base64 -d -A)\"); done
      exec \"\$C\" \"\${aa[@]}\""
  fi
}

# --- typed wrappers: encode the argument quirks once, so no caller can get them wrong -----

# cmux_tree — the surface tree with UUIDs. `--id-format` MUST follow the subcommand: placed
# before it, cmux exits 0 with EMPTY output, so a caller sees an empty tree and misdiagnoses
# whatever it was looking for. Non-empty output is enforced here rather than trusted.
cmux_tree() {
  local out
  out=$(run_cmux tree --all --id-format both 2>/dev/null) || return 1
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# cmux_rename_tab <surface-uuid> <title> — `tab.action` takes tab_id = a SURFACE uuid. Passing a
# workspace uuid returns "not_found: Workspace not found", which reads like a stale id and sends
# you hunting the wrong thing. Taking a surface id as the parameter name makes that unmistakable.
cmux_rename_tab() {
  local surface="$1" title="$2"
  [ -n "$surface" ] && [ -n "$title" ] || return 1
  run_cmux rpc tab.action \
    "$(jq -nc --arg s "$surface" --arg n "$title" '{action:"rename",tab_id:$s,title:$n}')" \
    >/dev/null 2>&1
}

# _cmux_ps <pid...> — process args for pids, on whichever host runs the cmux app.
_cmux_ps() {
  local csv
  csv=$(printf '%s,' "$@" | sed 's/,$//')
  [ -n "$csv" ] || return 1
  if [ -n "$(_cmux_local_bin)" ]; then
    ps -o pid=,args= -p "$csv" 2>/dev/null
  else
    # shellcheck disable=SC2029  # $csv is a pid list we built; expanding client-side is intended
    ssh -n "$CMUX_APP_HOST" "ps -o pid=,args= -p $csv" 2>/dev/null
  fi
}

# cmux_surface_for_zellij <zellij-session-name> — resolve a surface WITHOUT reading titles.
#
# `cmux top` maps each surface to the pids running in it; ps on the app host says which of those
# pids is the mosh/zellij client for our session. That chain is deterministic. Title matching is
# a heuristic that fails silently when a pane's title goes stale against the session actually
# running in it (a durable pane can be titled with a different zellij session entirely), so
# prefer this and keep titles as the fallback.
cmux_surface_for_zellij() {
  local zname="$1" top pids ps_out owner ref tree
  [ -n "$zname" ] || return 1
  top=$(run_cmux top --all --processes --flat --format tsv 2>/dev/null) || return 1
  # TSV columns: .. type(4) pid(5) owner-ref(6). Whitespace-joined rather than an array: this
  # lib is sourced from zsh as well as bash, and `mapfile` is bash-only.
  pids=$(printf '%s\n' "$top" |
    awk -F'\t' '$4=="process" && $6 ~ /^surface:/ {print $5}' | tr '\n' ' ')
  [ -n "${pids// /}" ] || return 1
  # shellcheck disable=SC2086  # deliberate word-split: $pids is a space-separated pid list
  ps_out=$(_cmux_ps $pids) || return 1
  # Match the name on a word boundary: a bare substring would let "…-12-fruity" hit
  # "…-12-fruity-emus" and resolve to the wrong pane.
  owner=$(printf '%s\n' "$ps_out" | awk -v n="$zname" '
    { if ($0 ~ ("[ /]" n "( |$)")) { print $1; exit } }')
  [ -n "$owner" ] || return 1
  ref=$(printf '%s\n' "$top" | awk -F'\t' -v p="$owner" '$4=="process" && $5==p {print $6; exit}')
  [ -n "$ref" ] || return 1
  tree=$(cmux_tree) || return 1
  printf '%s\n' "$tree" | awk -v r="$ref" '
    index($0, "surface " r " ") {
      if (match($0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/)) {
        print substr($0, RSTART, RLENGTH); exit
      }
    }'
}
