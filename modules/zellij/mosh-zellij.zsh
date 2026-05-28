# ssh::durable <host> [mosh-args...]
#
# Mosh into <host>, forwarding the local cmux workspace/surface ids and
# tagging the remote shell as CMUX_REMOTE_TRANSPORT=mosh. The remote
# auto-attach snippet treats `mosh` as an allowed transport and execs zellij
# into the matching session.
#
# Why not just `cmux ssh`? Cmux's ws relay has known per-keystroke overhead
# (cmux#4681 / cmux#4686) that makes zellij/tmux unusable over it. Mosh's UDP
# state-sync handles high-redraw TUIs without the latency.
#
# Nesting: if you run ssh::durable from inside a local zellij pane you end up
# nested. That's fine — local outer zellij + remote inner zellij both work;
# detach from the inner with the usual zellij keybinding when you're done.
ssh::durable() {
    emulate -L zsh
    if (( $# < 1 )); then
        print -u2 "usage: ssh::durable <host> [mosh-args...]"
        return 2
    fi
    if ! command -v mosh >/dev/null 2>&1; then
        print -u2 "ssh::durable: mosh not installed locally"
        return 127
    fi

    local host="$1"; shift

    local ws="${CMUX_WORKSPACE_ID}"
    local sf="${CMUX_SURFACE_ID}"
    if [[ -z $ws || -z $sf ]]; then
        if command -v uuidgen >/dev/null 2>&1; then
            : ${ws:=$(uuidgen)}
            : ${sf:=$(uuidgen)}
        else
            print -u2 "ssh::durable: CMUX_WORKSPACE_ID/CMUX_SURFACE_ID unset and uuidgen missing"
            return 1
        fi
    fi

    exec mosh "$@" "$host" -- \
        env \
        CMUX_WORKSPACE_ID="$ws" \
        CMUX_SURFACE_ID="$sf" \
        CMUX_REMOTE_TRANSPORT=mosh \
        zsh -l
}
