# cmux + zellij: auto-attach interactive cmux shells to a per-surface zellij session.
# Lives in zshrc-time (not zshenv) so /etc/zprofile's path_helper has already put
# /opt/homebrew/bin (and friends) on PATH, otherwise `command -v zellij` misses.
if [[ -n "$CMUX_WORKSPACE_ID" ]] && [[ -z "$ZELLIJ" ]] && [[ $- == *i* ]]; then
    if command -v zellij >/dev/null 2>&1; then
        zj_session="cmux-${USER}-${CMUX_WORKSPACE_ID}-${CMUX_SURFACE_ID}"
        zj_session="${zj_session//\//-}"
        zj_session="${zj_session// /-}"
        exec zellij attach -c "$zj_session"
    else
        print -P "%F{yellow}warning:%f cmux shell detected but zellij is not installed; skipping auto-attach (install via your dotfiles' zellij module)" >&2
    fi
fi
