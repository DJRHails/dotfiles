# cmux + zellij auto-attach
#
# Sourced at zshrc-time (not zshenv) so /etc/zprofile's path_helper has put
# /opt/homebrew/bin on PATH first, otherwise homebrew-installed zellij is
# invisible.
#
# Cmux's ssh relay (CMUX_REMOTE_TRANSPORT=ws) sets TERM=tmux-256color and
# TERM_PROGRAM=tmux because the relay impersonates tmux. Zellij sees that
# and switches to tmux-passthrough input handling which the cmux relay
# doesn't proxy, so the user can't type. We strip those before exec.
#
# Logs every invocation to ~/.cache/cmux-zellij/attempts.log.
# Circuit-breaker: if we tried to attach the same session within the last
# CMUX_ZELLIJ_MIN_INTERVAL seconds (default 3), abort instead of looping.

() {
    local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij"
    local logfile="$logdir/attempts.log"
    local min_interval="${CMUX_ZELLIJ_MIN_INTERVAL:-3}"

    [[ -d $logdir ]] || mkdir -p "$logdir" 2>/dev/null

    local _log
    _log() {
        printf '%s pid=%s ppid=%s host=%s ws=%s sf=%s transport=%s term=%s zellij=%s i=%s %s %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$PPID" "${HOST:-$(hostname -s)}" \
            "${CMUX_WORKSPACE_ID:-}" "${CMUX_SURFACE_ID:-}" "${CMUX_REMOTE_TRANSPORT:-local}" \
            "${TERM:-}" "${ZELLIJ:+set}" "$([[ $- == *i* ]] && echo y || echo n)" \
            "$1" "${2:-}" >> "$logfile" 2>/dev/null
    }

    if [[ -z $CMUX_WORKSPACE_ID ]]; then
        _log skip not-cmux
        return 0
    fi

    if [[ $CMUX_REMOTE_TRANSPORT == ws ]] && [[ -z $CMUX_ZELLIJ_OVER_SSH ]]; then
        # Known cmux bug: the ssh ws hot-path adds enough overhead that TUI
        # apps which hammer the pty (tmux, zellij) get severe input latency
        # or no input at all. Tracked upstream:
        #   https://github.com/manaflow-ai/cmux/issues/4681
        #   https://github.com/manaflow-ai/cmux/pull/4686
        #   https://github.com/manaflow-ai/cmux/issues/2969
        # Workaround: use `ssh::durable <host>` (modules/zellij/mosh-zellij.zsh)
        # which tunnels via mosh and sets CMUX_REMOTE_TRANSPORT=mosh which IS allowed.
        # Or flip CMUX_ZELLIJ_OVER_SSH=1 once the upstream fix lands.
        _log skip cmux-ssh-upstream-bug-4681
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

    # macOS UNIX socket paths cap at 103 bytes; zellij stuffs the session name
    # into $TMPDIR/zellij-$UID/contract_version_1/<session>. Two full UUIDs
    # blow the limit. Use 8-char prefixes plus TMPDIR=/tmp.
    local ws_short="${CMUX_WORKSPACE_ID[1,8]}"
    local sf_short="${CMUX_SURFACE_ID[1,8]}"
    local host_label="${HOST%%.*}"
    [[ -z $host_label ]] && host_label=$(hostname -s 2>/dev/null)
    host_label="${(L)host_label}"
    host_label="${host_label//[^a-z0-9-]/-}"
    local session="cmux-${host_label:-unknown}-${ws_short}-${sf_short}"
    session="${session//\//-}"
    session="${session// /-}"

    local stamp="$logdir/last-$session"
    if [[ -f $stamp ]]; then
        local now=$(date +%s) last=$(cat "$stamp" 2>/dev/null || echo 0)
        if (( now - last < min_interval )); then
            _log abort "loop-detected session=$session delta=$((now - last))s"
            print -P "%F{red}error:%f cmux+zellij auto-attach loop detected (session=$session, delta=$((now - last))s < ${min_interval}s); refusing. See $logfile" >&2
            return 0
        fi
    fi
    date +%s > "$stamp" 2>/dev/null

    local short_tmp="/tmp"
    [[ -d $short_tmp ]] || short_tmp="$TMPDIR"

    if [[ -n $CMUX_REMOTE_TRANSPORT ]]; then
        # cmux ssh relay impersonates tmux; zellij would talk tmux passthrough.
        _log attach "session=$session tmpdir=$short_tmp ssh-relay term-override=xterm-256color"
        TMPDIR="$short_tmp" TERM=xterm-256color TERM_PROGRAM= TERM_PROGRAM_VERSION= \
            exec zellij attach -c "$session"
    else
        _log attach "session=$session tmpdir=$short_tmp"
        TMPDIR="$short_tmp" exec zellij attach -c "$session"
    fi
}
