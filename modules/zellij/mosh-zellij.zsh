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

    # Unwrap: if we're inside a local zellij, spawn a sibling cmux workspace
    # that runs `mzj <host>` outside zellij. Local zellij stays running so the
    # user can switch back to it. We can't use `zellij action detach` and let
    # cmux respawn — cmux just closes the workspace instead of respawning.
    if [[ -n $ZELLIJ ]]; then
        if ! command -v cmux >/dev/null 2>&1; then
            print -u2 "mzj: inside zellij and no cmux CLI to spawn out — refusing to nest"
            return 1
        fi
        local skip_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij"
        mkdir -p "$skip_dir" 2>/dev/null
        touch "$skip_dir/skip-next-attach"
        local cmd_text="mzj ${(q-)host}"
        for a in "$@"; do
            cmd_text+=" ${(q-)a}"
        done
        print -u2 "mzj: spawning new cmux workspace 'mosh:$host' (local zellij left running)"
        # Do NOT exec here. When the requesting process dies, cmux appears to
        # cancel the new-workspace and the spawned workspace never materializes.
        # Run it as a sync child so the daemon commits before we return.
        if ! cmux new-workspace --name "mosh:$host" --command "$cmd_text" --focus true; then
            print -u2 "mzj: cmux new-workspace failed; keeping you in local zellij"
            rm -f "$skip_dir/skip-next-attach"
            return 1
        fi
        return 0
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
