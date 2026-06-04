# ssh::durable <host> [mosh-args...]
#
# Durable remote sessions: mosh into <host> and land in the right zellij session.
#
# cmux mints fresh workspace/surface UUIDs on every app restart, so the id-keyed
# session name changes and the old sessions are orphaned (they keep running). So we
# don't trust the forwarded ids — instead we show a picker of the host's live zellij
# sessions, each annotated with a one-line summary of what its panel is currently
# doing (fzf, with the live screen in the preview; ctrl-r re-summarises). Pick one and
# we mosh-attach it. Press Esc (or if there are no sessions) and we fall back to the
# legacy behaviour: forward the cmux ids and let the remote auto-attach snippet
# create/attach the id-designated session.
#
# Non-interactive / scriptable (for automation like `resurrect`):
#   ssh::durable <host> --list                 print "<session>\t<summary>" lines, no fzf, no attach
#   ssh::durable <host> --attach <session>     attach an exact session name, skip the picker
#   ssh::durable <host> --query <str> [mosh…]  attach the most-recent session whose menu line
#                                              matches <str> (case-insensitive); no match → fresh
# --attach/--query exec mosh when run outside a local zellij (via ssh::durable::go), so they
# still work as a cmux workspace --command; inside one they de-nest like the interactive path.
#
# Why mosh, not `cmux ssh`? Cmux's ws relay has known per-keystroke overhead
# (cmux#4681 / cmux#4686) that makes zellij/tmux unusable over it. Mosh's UDP
# state-sync handles high-redraw TUIs without the latency. We tag the remote with
# CMUX_REMOTE_TRANSPORT=mosh, which auto-attach.zsh treats as an allowed transport.
#
# Nesting: when invoked from inside the local zellij that auto-attach.zsh created for the cmux
# surface, we de-nest automatically — ssh::durable::go hands the mosh command to the surface's
# outer login shell and detaches the local zellij, so you end up with just the remote zellij
# (detach local → mosh → attach remote), not local-outer + remote-inner.
#
# Config (override in ~/.zshrc.local):
#   DURABLE_SUMMARY_MODEL   summariser model. Default: claude-haiku-4-5
#   DURABLE_SUMMARY_TTL     seconds before a cached summary is refreshed. Default: 300
#   DURABLE_SUMMARY_PAR     max concurrent summarisers on the host. Default: 6

: ${DURABLE_SUMMARY_MODEL:=claude-haiku-4-5}
: ${DURABLE_SUMMARY_TTL:=300}
: ${DURABLE_SUMMARY_PAR:=6}

# Draw a single-line progress bar on the tty from the remote's stderr progress events
# (DURABLE_TOTAL <n> then one DURABLE_TICK per finished summary). Anything else on
# stderr is passed through. The bar is cleared on EOF.
ssh::durable::render_progress() {
    emulate -L zsh
    local line bar k filled total=0 cnt=0 width=20
    local out=/dev/null; { : > /dev/tty } 2>/dev/null && out=/dev/tty
    while IFS= read -r line; do
        case $line in
            'DURABLE_TOTAL '*) total=${line#DURABLE_TOTAL } ;;
            'DURABLE_TICK')    (( cnt < total )) && (( cnt++ )) ;;
            *) [[ -n $line ]] && print -r -- "$line" >&2 ;;
        esac
        (( total > 0 )) || continue
        filled=$(( cnt * width / total ))
        bar=''; for (( k = 0; k < filled; k++ )); do bar+='#'; done
        printf '\r  titling sessions  [%-*s] %d/%d' "$width" "$bar" "$cnt" "$total" > $out
    done
    (( total > 0 )) && printf '\r\033[2K' > $out
}

# Fetch the host's live-session menu: tab-separated "<session-name>\t<summary>" lines,
# most-recent first (ordering owned by durable-remote.sh). Summaries are cached on the
# host for $DURABLE_SUMMARY_TTL. Progress bar goes to the tty (or /dev/null when scripted).
ssh::durable::menu() {
    emulate -L zsh
    local host="$1"
    local rscript="${DOTFILES:-$HOME/.files}/modules/zellij/durable-remote.sh"
    [[ -r $rscript ]] || { print -u2 "ssh::durable: missing $rscript"; return 1; }
    ssh "$host" sh -s -- "$host" "$DURABLE_SUMMARY_MODEL" "$DURABLE_SUMMARY_TTL" "$DURABLE_SUMMARY_PAR" 1 \
        < "$rscript" 2> >(ssh::durable::render_progress)
}

# Replace the surface with the durable command — but if we're nested inside a local zellij
# (auto-attach.zsh created one for this cmux surface), don't nest mosh inside it. Instead hand
# the command to the surface's outer login shell (the one that ran `zellij attach`) and detach
# this zellij so it drops back there; auto-attach.zsh execs the staged handoff. Net effect:
# detach local zellij → mosh → attach remote zellij, no nesting. Outside a local zellij (e.g.
# run as a cmux workspace --command) it just execs, exactly as before.
ssh::durable::go() {
    emulate -L zsh
    local cmdline="$1"
    if [[ -n $ZELLIJ && -n $ZELLIJ_SESSION_NAME ]]; then
        local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij"
        [[ -d $logdir ]] || mkdir -p "$logdir"
        print -r -- "$cmdline" > "$logdir/durable-handoff-${ZELLIJ_SESSION_NAME}"
        print -r -- "ssh::durable: detaching local zellij (${ZELLIJ_SESSION_NAME}) → durable hop …"
        zellij action detach
        return 0
    fi
    eval "exec ${cmdline}"
}

# Attach an exact session by name (mosh + zellij attach). De-nests via ssh::durable::go when
# inside a local zellij, else execs — so it's still safe as a cmux workspace --command.
# Trailing args are passed to mosh.
ssh::durable::attach() {
    emulate -L zsh
    local host="$1" sess="$2"; shift 2
    print -r -- "ssh::durable: attaching ${sess} on ${host} …"
    ssh::durable::write_live_ids "$host" "$sess"
    ssh::durable::go "mosh ${(j: :)${(@q)@}} ${(q)host} -- zellij attach ${(q)sess}"
}

# Legacy fallback: mosh in, forward cmux ids, let the remote auto-attach the designated
# session (creating it if needed). Used when nothing is picked or no sessions exist.
ssh::durable::fresh() {
    emulate -L zsh
    local host="$1"; shift
    local ws="${CMUX_WORKSPACE_ID}" sf="${CMUX_SURFACE_ID}"
    if [[ -z $ws || -z $sf ]]; then
        if command -v uuidgen >/dev/null 2>&1; then
            : ${ws:=$(uuidgen)}
            : ${sf:=$(uuidgen)}
        else
            print -u2 "ssh::durable: CMUX_WORKSPACE_ID/CMUX_SURFACE_ID unset and uuidgen missing"
            return 1
        fi
    fi
    ssh::durable::go "mosh ${(j: :)${(@q)@}} ${(q)host} -- env CMUX_WORKSPACE_ID=${(q)ws} CMUX_SURFACE_ID=${(q)sf} CMUX_REMOTE_TRANSPORT=mosh zsh -l"
}

# Persist THIS cmux surface's live ids on the remote so remote cmux tools (cmux-session-tab /
# fork) can target the current app surface even though the durable session's $CMUX_* env is
# frozen at creation and goes stale when cmux re-mints UUIDs. Keyed by the zellij session name,
# matching auto-attach.zsh's sidecar path. Best-effort; never blocks the attach.
ssh::durable::write_live_ids() {
    emulate -L zsh
    local host="$1" sess="$2"
    [[ -n $CMUX_SURFACE_ID && -n $sess ]] || return 0
    local dir='${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij'
    ssh "$host" "mkdir -p $dir && printf '%s %s\n' ${(q)CMUX_WORKSPACE_ID} ${(q)CMUX_SURFACE_ID} > $dir/live-${(q)sess}" 2>/dev/null || true
}

ssh::durable() {
    emulate -L zsh
    if (( $# < 1 )); then
        print -u2 "usage: ssh::durable <host> [--list | --attach <session> | --query <str>] [mosh-args...]"
        return 2
    fi
    if ! command -v mosh >/dev/null 2>&1; then
        print -u2 "ssh::durable: mosh not installed locally"
        return 127
    fi
    local host="$1"; shift

    # Non-interactive selectors for automation. These short-circuit the fzf picker.
    case "$1" in
        --list|--ls)
            ssh::durable::menu "$host"
            return $?
            ;;
        --attach|-a)
            shift
            local sess="$1"; shift
            if [[ -z $sess ]]; then
                print -u2 "ssh::durable: --attach needs a session name"
                return 2
            fi
            ssh::durable::attach "$host" "$sess" "$@"
            ;;
        --query|-q)
            shift
            local query="$1"; shift
            if [[ -z $query ]]; then
                print -u2 "ssh::durable: --query needs a match string"
                return 2
            fi
            local line
            line=$(ssh::durable::menu "$host" | grep -i -m1 -- "$query")
            if [[ -n $line ]]; then
                ssh::durable::attach "$host" "${line%%$'\t'*}" "$@"
            fi
            print -u2 "ssh::durable: no session matching '${query}' on ${host} — starting fresh"
            ssh::durable::fresh "$host" "$@"
            ;;
    esac

    local rscript="${DOTFILES:-$HOME/.files}/modules/zellij/durable-remote.sh"

    # Picker path: needs fzf locally and the remote generator script.
    if command -v fzf >/dev/null 2>&1 && [[ -r $rscript ]]; then
        local menu
        menu=$(ssh::durable::menu "$host")
        { : > /dev/tty } 2>/dev/null && printf '\r\033[2K' > /dev/tty
        if [[ -n $menu ]]; then
            local reload="ssh ${(q)host} sh -s -- ${(q)host} ${(q)DURABLE_SUMMARY_MODEL} 0 ${(q)DURABLE_SUMMARY_PAR} < ${(q)rscript}"
            local preview="ssh ${(q)host} sh -s -- --preview {1} < ${(q)rscript}"
            local chosen
            chosen=$(print -r -- "$menu" | fzf \
                --ansi --delimiter=$'\t' --with-nth=2 \
                --prompt="durable@${host}> " \
                --header='enter: attach · ctrl-r: re-summarise · esc: new session' \
                --height=90% --border --reverse \
                --preview "$preview" --preview-window='right:62%:wrap' \
                --bind "ctrl-r:reload($reload)")
            if [[ -n $chosen ]]; then
                ssh::durable::attach "$host" "${chosen%%$'\t'*}" "$@"
            fi
            # Esc / no pick → fall through to a fresh session.
        fi
    fi

    ssh::durable::fresh "$host" "$@"
}
