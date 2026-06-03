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

    local host_label="${HOST%%.*}"
    [[ -z $host_label ]] && host_label=$(hostname -s 2>/dev/null)
    host_label="${(L)host_label}"
    host_label="${host_label//[^a-z0-9-]/-}"

    # Readable session id via the user's `humane` lib (`humane id --short <seed>`),
    # seeded deterministically by the surface UUID so re-runs of THIS surface hit the
    # same session. cmux re-mints UUIDs per app-restart, so the id still changes across
    # app sessions like the old hex did (the picker re-attaches orphans) — this just makes
    # names legible: cmux-<host>-9-trim-lobsters instead of cmux-<host>-F79079CA-D38DFEEB.
    # Falls back to the 8-char hex pair if humane isn't installed, so attach never breaks.
    # (Stays well under the 103-byte macOS UNIX-socket path cap; TMPDIR=/tmp below.)
    local id_part
    if command -v humane >/dev/null 2>&1; then
        id_part="$(humane id --short "$CMUX_SURFACE_ID" 2>/dev/null)"
    fi
    [[ -z $id_part ]] && id_part="${CMUX_WORKSPACE_ID[1,8]}-${CMUX_SURFACE_ID[1,8]}"
    id_part="${(L)id_part//[^a-z0-9-]/-}"
    local session="cmux-${host_label:-unknown}-${id_part}"
    session="${session//\//-}"
    session="${session// /-}"

    # Explicit session override: lets tooling bind THIS surface to a specific session
    # (e.g. resurrect an existing one) instead of the default UUID-derived name. Checks
    # $CMUX_ZELLIJ_SESSION first, then a one-shot marker file keyed by surface id
    # (written before the surface's shell starts). The marker is consumed on read so the
    # rebind happens once, not on every resurrect.
    local override_file="$logdir/override-${CMUX_SURFACE_ID}"
    if [[ -n $CMUX_ZELLIJ_SESSION ]]; then
        session="$CMUX_ZELLIJ_SESSION"
        _log override "env session=$session"
    elif [[ -f $override_file ]]; then
        local override_name="$(<"$override_file")"
        rm -f "$override_file"
        if [[ -n $override_name ]]; then
            session="$override_name"
            _log override "file session=$session"
        fi
    fi

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

    # Live cmux-ids sidecar: cmux re-mints workspace/surface UUIDs per app-restart, so the
    # forwarded $CMUX_* env goes stale. Persist the *current* ids (live on this fresh attach)
    # keyed by session name, so remote cmux tools (cmux-session-tab / fork) target the current
    # app surface regardless of the stale env. The picker re-attach path writes this too.
    print -r -- "${CMUX_WORKSPACE_ID} ${CMUX_SURFACE_ID}" > "$logdir/live-$session" 2>/dev/null

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
