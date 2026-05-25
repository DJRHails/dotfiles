# cmux + zellij auto-attach
#
# Lives in zshrc-time (not zshenv) so /etc/zprofile's path_helper has put
# /opt/homebrew/bin on PATH first, otherwise homebrew-installed zellij is
# invisible.
#
# Logs every invocation to ~/.cache/cmux-zellij/attempts.log.
# Circuit-breaker: if we tried to attach the same session within the last
# CMUX_ZELLIJ_MIN_INTERVAL seconds, abort instead of loop.

() {
    local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij"
    local logfile="$logdir/attempts.log"
    local min_interval="${CMUX_ZELLIJ_MIN_INTERVAL:-3}"

    [[ -d $logdir ]] || mkdir -p "$logdir" 2>/dev/null

    local _log
    _log() {
        # ts pid ppid host workspace surface zellij_set interactive action detail
        printf '%s pid=%s ppid=%s host=%s ws=%s sf=%s zellij=%s i=%s %s %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$PPID" "${HOST:-$(hostname -s)}" \
            "${CMUX_WORKSPACE_ID:-}" "${CMUX_SURFACE_ID:-}" \
            "${ZELLIJ:+set}" "$([[ $- == *i* ]] && echo y || echo n)" \
            "$1" "${2:-}" >> "$logfile" 2>/dev/null
    }

    if [[ -z $CMUX_WORKSPACE_ID ]]; then
        _log skip not-cmux
        return 0
    fi

    if [[ -n $ZELLIJ ]]; then
        _log skip already-in-zellij
        return 0
    fi

    if [[ $- != *i* ]]; then
        _log skip non-interactive
        return 0
    fi

    if ! command -v zellij >/dev/null 2>&1; then
        _log skip no-zellij-binary
        print -P "%F{yellow}warning:%f cmux shell detected but zellij is not installed; skipping auto-attach" >&2
        return 0
    fi

    local session="cmux-${USER}-${CMUX_WORKSPACE_ID}-${CMUX_SURFACE_ID}"
    session="${session//\//-}"
    session="${session// /-}"

    local stamp="$logdir/last-$session"
    if [[ -f $stamp ]]; then
        local now=$(date +%s) last=$(cat "$stamp" 2>/dev/null || echo 0)
        if (( now - last < min_interval )); then
            _log abort "loop-detected session=$session delta=$((now - last))s"
            print -P "%F{red}error:%f cmux+zellij auto-attach loop detected (session=$session, delta=$((now - last))s < ${min_interval}s); refusing to attach. See $logfile" >&2
            return 0
        fi
    fi
    date +%s > "$stamp" 2>/dev/null

    _log attach "session=$session"
    exec zellij attach -c "$session"
}
