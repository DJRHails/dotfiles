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
# Why mosh, not `cmux ssh`? Cmux's ws relay has known per-keystroke overhead
# (cmux#4681 / cmux#4686) that makes zellij/tmux unusable over it. Mosh's UDP
# state-sync handles high-redraw TUIs without the latency. We tag the remote with
# CMUX_REMOTE_TRANSPORT=mosh, which auto-attach.zsh treats as an allowed transport.
#
# Nesting: running this from inside a local zellij pane nests (local outer + remote
# inner). That's fine — detach the inner with the usual zellij keybinding.
#
# Config (override in ~/.zshrc.local):
#   DURABLE_SUMMARY_MODEL   summariser model. Default: claude-haiku-4-5
#   DURABLE_SUMMARY_TTL     seconds before a cached summary is refreshed. Default: 300
#   DURABLE_SUMMARY_PAR     max concurrent summarisers on the host. Default: 6

: ${DURABLE_SUMMARY_MODEL:=claude-haiku-4-5}
: ${DURABLE_SUMMARY_TTL:=300}
: ${DURABLE_SUMMARY_PAR:=6}

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
    exec mosh "$@" "$host" -- \
        env CMUX_WORKSPACE_ID="$ws" CMUX_SURFACE_ID="$sf" CMUX_REMOTE_TRANSPORT=mosh \
        zsh -l
}

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

    local rscript="${DOTFILES:-$HOME/.files}/modules/zellij/durable-remote.sh"

    # Picker path: needs fzf locally and the remote generator script.
    if command -v fzf >/dev/null 2>&1 && [[ -r $rscript ]]; then
        local menu
        menu=$(ssh "$host" sh -s -- "$host" "$DURABLE_SUMMARY_MODEL" "$DURABLE_SUMMARY_TTL" "$DURABLE_SUMMARY_PAR" < "$rscript")
        if [[ -n $menu ]]; then
            local reload="ssh ${(q)host} sh -s -- ${(q)host} ${(q)DURABLE_SUMMARY_MODEL} 0 ${(q)DURABLE_SUMMARY_PAR} < ${(q)rscript}"
            local preview="ssh ${(q)host} 'zellij -s {1} action dump-screen 2>/dev/null | tail -n 200'"
            local chosen
            chosen=$(print -r -- "$menu" | fzf \
                --ansi --delimiter=$'\t' --with-nth=2 \
                --prompt="durable@${host}> " \
                --header='enter: attach · ctrl-r: re-summarise · esc: new session' \
                --height=90% --border --reverse \
                --preview "$preview" --preview-window='right:62%:wrap' \
                --bind "ctrl-r:reload($reload)")
            if [[ -n $chosen ]]; then
                local sess="${chosen%%$'\t'*}"
                print -r -- "ssh::durable: attaching ${sess} on ${host} …"
                exec mosh "$@" "$host" -- zellij attach "$sess"
            fi
            # Esc / no pick → fall through to a fresh session.
        fi
    fi

    ssh::durable::fresh "$host" "$@"
}
