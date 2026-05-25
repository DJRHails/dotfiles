# mzj <host> [mosh-args...]
#
# Mosh into <host> while forwarding the local cmux workspace/surface ids and
# tagging the remote shell as CMUX_REMOTE_TRANSPORT=mosh. The remote
# auto-attach snippet (modules/zellij/auto-attach.zsh) treats `mosh` as an
# allowed transport and execs zellij into the matching session.
#
# Why not just `cmux ssh`? Cmux's ws relay has known per-keystroke overhead
# (cmux#4681 / cmux#4686) that makes zellij/tmux unusable over it. Mosh's UDP
# state-sync handles high-redraw TUIs without the latency.
#
# Stable session naming: if launched from inside a local cmux surface, the
# session name reuses CMUX_WORKSPACE_ID/CMUX_SURFACE_ID so reconnects land in
# the same zellij session. Outside cmux we synthesize uuids — those won't be
# reproducible across launches.
mzj() {
    emulate -L zsh
    if (( $# < 1 )); then
        print -u2 "usage: mzj <host> [mosh-args...]"
        return 2
    fi
    if ! command -v mosh >/dev/null 2>&1; then
        print -u2 "mzj: mosh not installed locally"
        return 127
    fi

    local host="$1"; shift

    # Unwrap: if we're already inside a local zellij, step out of it and queue
    # the mosh action. After detach, the cmux surface respawns a fresh shell
    # which sources zshrc, the auto-attach snippet sees the queue file, and
    # exec's `mzj <host> ...` outside zellij — proceeding to the normal path.
    if [[ -n $ZELLIJ ]]; then
        if [[ -z $CMUX_SURFACE_ID ]]; then
            print -u2 "mzj: inside zellij but no CMUX_SURFACE_ID — cannot queue unwrap; refusing to nest"
            return 1
        fi
        local queue_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij"
        local queue_file="$queue_dir/queue-${CMUX_SURFACE_ID}"
        mkdir -p "$queue_dir" 2>/dev/null
        # Format: mzj|<host>|<arg1>|<arg2>|...
        local -a queue_parts=(mzj "$host" "$@")
        print -r -- "${(j.|.)queue_parts}" > "$queue_file"
        print -u2 "mzj: stepping out of local zellij; will mosh to $host on respawn"
        exec zellij action detach
    fi

    local ws="${CMUX_WORKSPACE_ID}"
    local sf="${CMUX_SURFACE_ID}"
    if [[ -z $ws || -z $sf ]]; then
        if command -v uuidgen >/dev/null 2>&1; then
            : ${ws:=$(uuidgen)}
            : ${sf:=$(uuidgen)}
        else
            print -u2 "mzj: CMUX_WORKSPACE_ID/CMUX_SURFACE_ID unset and uuidgen missing"
            return 1
        fi
    fi

    # mosh runs <command> as the user's process on the remote pty. We chain
    # env(1) to inject CMUX_* before zsh sources zshrc, so the auto-attach
    # snippet sees them.
    exec mosh "$@" "$host" -- \
        env \
        CMUX_WORKSPACE_ID="$ws" \
        CMUX_SURFACE_ID="$sf" \
        CMUX_REMOTE_TRANSPORT=mosh \
        zsh -l
}
