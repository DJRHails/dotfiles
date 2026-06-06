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
#
# Escape hatches (so a non-zellij shell is always reachable):
#   - CMUX_NO_ZELLIJ=1  -> skip auto-attach entirely for this surface.
#   - Detach/quit returns to a plain shell in the same surface (we don't
#     `exec` zellij), instead of closing the window.

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

    # Opt-out: set CMUX_NO_ZELLIJ=1 (globally, or per workspace/surface env) for a
    # plain, zellij-free shell in this surface.
    if [[ -n $CMUX_NO_ZELLIJ ]]; then
        _log skip opt-out-no-zellij
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

    # ssh::durable forwards the local cwd's path relative to the local $PROJECTS as
    # CMUX_DURABLE_CD so a *fresh* durable session lands in the matching project here.
    # Resolve it against THIS host's $PROJECTS (which may be a colon-separated list and may
    # differ from the origin's); cd before zellij starts so the new session's first pane
    # inherits the dir. Warn (don't fail) if the subpath isn't present on this host. Only the
    # top-level durable shell reaches this — nested panes already returned at the $ZELLIJ check.
    if [[ -n $CMUX_DURABLE_CD ]]; then
        local sub="$CMUX_DURABLE_CD"; unset CMUX_DURABLE_CD
        local root target='' first=''
        for root in ${(s.:.)PROJECTS}; do
            root="${root%/}"; [[ -n $root ]] || continue
            [[ -z $first ]] && first="$root"
            if [[ -d $root/$sub ]]; then target="$root/$sub"; break; fi
        done
        if [[ -n $target ]]; then
            cd -- "$target"; _log durable-cd "target=$target"
        elif [[ -n $first ]]; then
            print -P "%F{yellow}warning:%f ssh::durable: '${sub}' not found under \$PROJECTS (${first}) on this host" >&2
            _log durable-cd-missing "sub=$sub"
        fi
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

    # Durable de-nest handoff: when `ssh::durable` is invoked from *inside* this local zellij,
    # it stages a mosh command in $handoff and detaches us, so on return we replace the surface
    # with that durable hop instead of nesting mosh inside zellij. Cleared first so a stale one
    # never fires; consumed below.
    local handoff="$logdir/durable-handoff-$session"
    rm -f "$handoff" 2>/dev/null

    if [[ -n $CMUX_REMOTE_TRANSPORT ]]; then
        # cmux ssh relay impersonates tmux; zellij would talk tmux passthrough.
        _log attach "session=$session tmpdir=$short_tmp ssh-relay term-override=xterm-256color"
        TMPDIR="$short_tmp" TERM=xterm-256color TERM_PROGRAM= TERM_PROGRAM_VERSION= \
            zellij attach -c "$session"
    else
        _log attach "session=$session tmpdir=$short_tmp"
        TMPDIR="$short_tmp" zellij attach -c "$session"
    fi

    # If ssh::durable staged a durable hop, replace the surface with it (de-nest: detach local
    # zellij → mosh → attach remote). Otherwise fall through to the plain-shell behaviour below.
    if [[ -f $handoff ]]; then
        local hop="$(<"$handoff")"
        rm -f "$handoff" 2>/dev/null
        _log durable-hop "session=$session"
        eval "exec ${hop}"
    fi

    # Intentionally NOT `exec`: on detach (Ctrl+O d / `zellij action detach`) or
    # quit, control returns here, the rest of zshrc runs, and you land in a plain
    # non-zellij shell in the SAME surface instead of the window closing.
    # Re-attach with `zja` / `zellij attach -c "$session"`.
    _log detached "session=$session"
}
