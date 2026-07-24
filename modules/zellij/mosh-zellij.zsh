# ssh::durable <host> [mosh-args...]
#
# Durable remote sessions: mosh into <host> and land in the right zellij session.
#
# cmux mints fresh workspace/surface UUIDs on every app restart, so the id-keyed
# session name changes and the old sessions are orphaned (they keep running). So we
# don't trust the forwarded ids — instead we show a picker of the host's live zellij sessions.
# Each row is its cwd fragment (last two path components) + a 3-5 word AI title; the preview shows
# the full one-line summary, the full cwd, and the live screen. ctrl-r re-summarises; ctrl-x kills
# the selected session (confirm prompt). A green ● marks sessions with a live mosh client, and the
# header shows the connected count. Pick one and we mosh-attach it. Press Esc (or if there are no
# sessions) and we fall back to the legacy behaviour: forward the cmux ids and let the remote
# auto-attach snippet create/attach the id-designated session.
#
# Non-interactive / scriptable (for automation like `resurrect`):
#   ssh::durable <host> --list                 print "<session>\t<summary>" lines, no fzf, no attach
#   ssh::durable <host> --attach <session>     attach an exact session name, skip the picker
#   ssh::durable <host> --query <str> [mosh…]  attach the most-recent session whose menu line
#                                              contains <str> (case-insensitive fixed string,
#                                              not a regex); no match → fresh
#   ssh::durable <host> --reap                 kill orphaned (disconnected, >120s) mosh-servers;
#                                              ~60s, safe to loop. Opt-in only — NOT auto-fired, so
#                                              it can never drop a still-attached tab.
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
# Project-dir matching: when invoked from a directory under your local $PROJECTS, a *fresh*
# durable session lands in the matching project on the remote — the subpath relative to
# $PROJECTS is forwarded as CMUX_DURABLE_CD and resolved by auto-attach.zsh against the remote's
# own $PROJECTS (which may differ). A warning prints on the remote if the subpath isn't there.
# Only the fresh path cds; picking an existing session resumes it wherever it already is.
#
# Config (override in ~/.zshrc.local):
#   DURABLE_SUMMARY_MODEL   summariser model. Default: claude-haiku-4-5
#   DURABLE_SUMMARY_TTL     seconds before a cached summary is refreshed. Default: 300
#   DURABLE_SUMMARY_PAR     max concurrent summarisers on the host. Default: 8

: ${DURABLE_SUMMARY_MODEL:=claude-haiku-4-5}
: ${DURABLE_SUMMARY_TTL:=300}
: ${DURABLE_SUMMARY_PAR:=8}

# Apply a progressive menu stream to a mirror file. Each input line is "<session>\t<label>";
# we upsert by session (keeping the newest-first order of the first snapshot) and rewrite the
# mirror after every line — so an fzf polling the mirror sees cwds and summaries fill in live.
ssh::durable::stream_apply() {
    emulate -L zsh
    local mirror="$1" autherr="$2" statusf="$3" raw sess k
    local -a order; local -A line
    while IFS= read -r raw; do
        [[ -n $raw ]] || continue
        if [[ $raw == '__AUTHFAIL__'* ]]; then
            print -r -- "${raw#__AUTHFAIL__$'\t'}" > "$autherr"
            continue
        fi
        if [[ $raw == '__STATUS__'* ]]; then
            print -r -- "${raw#__STATUS__$'\t'}" > "$statusf"
            continue
        fi
        sess=${raw%%$'\t'*}
        (( ${+line[$sess]} )) || order+=("$sess")
        line[$sess]=$raw
        { for k in $order; do print -r -- "$line[$k]"; done } > "$mirror.tmp" && mv -f "$mirror.tmp" "$mirror"
    done
}

# Ports of local mosh-clients connected to $1 (host): a mosh-client's last arg is the host port,
# and a client for this host carries the host string in its args. Used to mark connected sessions
# exactly (a session whose mosh-server holds one of these ports has a live client right here).
ssh::durable::live_ports() {
    emulate -L zsh
    ps -axww -o command= 2>/dev/null \
        | awk -v h="$1" '$1 ~ /mosh-client$/ && index($0, h) {print $NF}' \
        | sort -u | tr '\n' ' '
}

# Background feeder for the picker. Streams the host's session menu into $mirror (see
# ssh::durable::stream_apply) then touches $done. Idles until ctrl-r touches $req, then
# re-streams with ttl=0 (force re-summarise). Exits when $quit appears. Records the live
# ssh-pipeline pid in $pidf so the caller can kill an in-flight refresh on teardown.
ssh::durable::stream_supervisor() {
    emulate -L zsh
    local host="$1" mirror="$2" done="$3" req="$4" quit="$5" pidf="$6" autherr="$7" statusf="$8"
    local rscript="${DOTFILES:-$HOME/.files}/modules/zellij/durable-remote.sh"
    [[ -r $rscript ]] || { print -u2 "ssh::durable: missing $rscript"; : > "$done"; return 1; }
    local ttl pp lp
    while [[ ! -f $quit ]]; do
        ttl=$DURABLE_SUMMARY_TTL
        [[ -f $req ]] && { ttl=0; command rm -f "$req" "$autherr"; }
        command rm -f "$done"
        lp=$(ssh::durable::live_ports "$host")  # recomputed each stream so the ● stays current
        # ${(q)lp} is load-bearing: $lp is a space-separated port list, and ssh flattens its argv
        # into one string the remote shell re-splits — so an unquoted "$lp" arrives as N args and
        # the remote only reads $6 (the first port). That made the ● mark a single session. Quote it
        # so the whole list survives as one remote arg.
        ssh "$host" sh -s -- --stream "$host" "$DURABLE_SUMMARY_MODEL" "$ttl" "$DURABLE_SUMMARY_PAR" "${(q)lp}" \
            < "$rscript" 2>/dev/null | ssh::durable::stream_apply "$mirror" "$autherr" "$statusf" &
        pp=$!
        print -r -- "$pp" > "$pidf"
        wait $pp
        : > "$done"
        while [[ ! -f $req && ! -f $quit ]]; do sleep 0.3; done
    done
}

# Batch menu for automation (--list/--query): refresh everything on the host, then print the
# final "<session>\t<label>" lines once (most-recent first). No streaming, no progress UI.
ssh::durable::menu_list() {
    emulate -L zsh
    local host="$1"
    local rscript="${DOTFILES:-$HOME/.files}/modules/zellij/durable-remote.sh"
    [[ -r $rscript ]] || { print -u2 "ssh::durable: missing $rscript"; return 1; }
    ssh "$host" sh -s -- --list "$host" "$DURABLE_SUMMARY_MODEL" "$DURABLE_SUMMARY_TTL" "$DURABLE_SUMMARY_PAR" \
        < "$rscript" 2>/dev/null
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
    # Rebind the surface's resume command so a cmux restart re-moshes THIS session here
    # (see the binding block in auto-attach.zsh). Backgrounded — survives the exec below.
    if [[ -z $CMUX_REMOTE_TRANSPORT ]] && command -v cmux >/dev/null 2>&1; then
        { cmux surface resume set --kind zellij-mosh --name "$sess" \
            --shell "mosh ${(q)host} -- zellij attach ${(q)sess}" } >/dev/null 2>&1 &!
    fi
    ssh::durable::go "mosh ${(j: :)${(@q)@}} ${(q)host} -- zellij attach ${(q)sess}"
}

# zellij::resume <session> — reattach a detached LOCAL zellij session in this cmux surface.
# The local analogue of `ssh::durable <host> --attach`: reuses the durable de-nest handoff
# (ssh::durable::go), so from inside the surface's auto-attach wrapper it stages the attach,
# detaches, and auto-attach.zsh deletes the wrapper husk and execs `zellij attach <session>`.
# Outside a wrapper it just execs. Used by rebuild-durable.py for the cmux host's own sessions.
zellij::resume() {
    emulate -L zsh
    local sess="$1"
    if [[ -z $sess ]]; then
        print -u2 "usage: zellij::resume <session>"
        return 2
    fi
    # Same live-ids sidecar ssh::durable::write_live_ids maintains on remotes: the session's
    # $CMUX_* env froze at creation, so persist THIS surface's current ids for cmux tooling.
    if [[ -n $CMUX_WORKSPACE_ID && -n $CMUX_SURFACE_ID ]]; then
        local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij"
        [[ -d $logdir ]] || mkdir -p "$logdir" 2>/dev/null
        { print -r -- "${CMUX_WORKSPACE_ID} ${CMUX_SURFACE_ID}" > "$logdir/live-$sess" } 2>/dev/null
    fi
    print -r -- "zellij::resume: attaching ${sess} …"
    # TMPDIR=/tmp matches auto-attach.zsh: zellij's socket dir follows TMPDIR, and the surface
    # shell's default (/var/folders/…) can't see sessions created under /tmp — the exec'd attach
    # would exit "not found" and close the surface. Also keeps under the UNIX-socket path cap.
    local short_tmp="/tmp"
    [[ -d $short_tmp ]] || short_tmp="$TMPDIR"
    # Rebind the surface's resume command so a cmux restart restores THIS session here
    # (see the binding block in auto-attach.zsh). Backgrounded — survives the exec below.
    if [[ -z $CMUX_REMOTE_TRANSPORT ]] && command -v cmux >/dev/null 2>&1; then
        { cmux surface resume set --kind zellij --name "$sess" --cwd "$PWD" \
            --shell "env TMPDIR=${short_tmp} zellij attach ${(q)sess}" } >/dev/null 2>&1 &!
    fi
    ssh::durable::go "env TMPDIR=${(q)short_tmp} zellij attach ${(q)sess}"
}

# If the local cwd is under $PROJECTS, echo its path relative to $PROJECTS (e.g.
# "github.com/DJRHails/touchstone"); else echo nothing. $PROJECTS may be a colon-separated
# list of roots; the first one that prefixes $PWD wins. The remote resolves this subpath
# against ITS OWN $PROJECTS, so a fresh durable session lands in the matching project even
# when the project root differs across machines.
ssh::durable::project_subpath() {
    emulate -L zsh
    [[ -n $PROJECTS ]] || return 0
    local root
    for root in ${(s.:.)PROJECTS}; do
        root="${root%/}"
        [[ -n $root ]] || continue
        case $PWD in
            "$root"/*) print -r -- "${PWD#"$root"/}"; return 0 ;;
        esac
    done
}

# Legacy fallback: mosh in, forward cmux ids, let the remote auto-attach the designated
# session (creating it if needed). Used when nothing is picked or no sessions exist. Also
# forwards the $PROJECTS-relative subpath so a freshly-created session lands in the matching
# project dir on the remote (see ssh::durable::project_subpath / auto-attach.zsh).
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
    local env_prefix="CMUX_WORKSPACE_ID=${(q)ws} CMUX_SURFACE_ID=${(q)sf} CMUX_REMOTE_TRANSPORT=mosh"
    local sub; sub=$(ssh::durable::project_subpath)
    [[ -n $sub ]] && env_prefix="CMUX_DURABLE_CD=${(q)sub} ${env_prefix}"
    ssh::durable::go "mosh ${(j: :)${(@q)@}} ${(q)host} -- env ${env_prefix} zsh -l"
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
            ssh::durable::menu_list "$host"
            return $?
            ;;
        --reap|--sweep-mosh)
            # Reap disconnected mosh-servers (no live local client, >120s old) on the host. Opt-in
            # cleanup only — drops stale transports; the zellij sessions persist and re-mosh on the
            # next attach. The green ● is computed fresh by the picker on each open, independent of
            # this.
            local rscript="${DOTFILES:-$HOME/.files}/modules/zellij/durable-remote.sh"
            [[ -r $rscript ]] || { print -u2 "ssh::durable: missing $rscript"; return 1; }
            local reap_force=""
            [[ "${2:-}" == (--force|-f) || -n ${DURABLE_REAP_FORCE:-} ]] && reap_force=1
            local reap_lp; reap_lp="$(ssh::durable::live_ports "$host")"
            # Without a single live mosh-client to $host *from this machine*, the remote reap would
            # see an empty port list and treat every server as orphaned. Refuse here too (the remote
            # guards as well — defense in depth) unless explicitly forced. Run --reap from the host
            # actually attached to the sessions, or pass --force for a deliberate mass cleanup.
            if [[ -z $reap_lp && $reap_force != 1 ]]; then
                print -u2 "ssh::durable --reap: no live mosh-client to $host from this host — refusing (would target every server). Run from the attached host, or pass --force."
                return 0
            fi
            # ${(q)reap_lp} for the same reason as the stream path: an unquoted space-separated
            # port list is flattened by ssh and the remote reads only its first port — which made
            # the reap treat every other server as orphaned and kill it. Quote it intact.
            ssh "$host" flock -n /tmp/durable-reap.lock sh -s -- --reap "${(q)reap_lp}" "$reap_force" < "$rscript"
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
            return
            ;;
        --query|-q)
            shift
            local query="$1"; shift
            if [[ -z $query ]]; then
                print -u2 "ssh::durable: --query needs a match string"
                return 2
            fi
            local line
            # -F: fixed-string match — without it a '.' over-matches and a '[' in the
            # query is a regex error (grep exit 2), silently falling through to fresh.
            # The menu line includes the cwd, so --query matches by directory too.
            line=$(ssh::durable::menu_list "$host" | grep -iF -m1 -- "$query")
            if [[ -n $line ]]; then
                ssh::durable::attach "$host" "${line%%$'\t'*}" "$@"
                return
            fi
            print -u2 "ssh::durable: no session matching '${query}' on ${host} — starting fresh"
            ssh::durable::fresh "$host" "$@"
            return
            ;;
    esac

    local rscript="${DOTFILES:-$HOME/.files}/modules/zellij/durable-remote.sh"

    # Picker path: open fzf immediately on a cached snapshot (session ids + cwds), then stream
    # cwds and AI summaries in live as the host computes them. Needs fzf and the remote script.
    if command -v fzf >/dev/null 2>&1 && [[ -r $rscript ]]; then
        local tmpd; tmpd=$(mktemp -d "${TMPDIR:-/tmp}/durable.XXXXXX")
        local mirror="$tmpd/menu" done="$tmpd/done" req="$tmpd/req" quit="$tmpd/quit"
        local pidf="$tmpd/pid" autherr="$tmpd/autherr" sig="$tmpd/sig" poll="$tmpd/poll.sh"
        local statusf="$tmpd/statusf" killed="$tmpd/killed" show="$tmpd/show.sh" killsh="$tmpd/kill.sh"
        : > "$mirror"; : > "$killed"

        # show.sh: print the mirror minus any ctrl-x-killed sessions (field 1 ∈ $killed). Every
        # display path goes through this so a killed session vanishes and never comes back.
        cat > "$show" <<'SHOW'
#!/bin/sh
awk -F'\t' -v kf="$2" 'BEGIN{while((getline l < kf)>0) k[l]=1} !($1 in k)' "$1"
SHOW
        # poll.sh: debounce — block until the mirror's (mtime+size) signature changes or $done
        # lands, then print it (killed-filtered) — so fzf redraws only on real updates, not a timer.
        cat > "$poll" <<'POLL'
#!/bin/sh
m=$1 d=$2 sig=$3 killed=$4
last=$(cat "$sig" 2>/dev/null || echo init)
while :; do
  cur=$(stat -c '%Y %s' "$m" 2>/dev/null || stat -f '%m %z' "$m" 2>/dev/null || echo 0)
  { [ "$cur" != "$last" ] || [ -f "$d" ]; } && break
  sleep 0.3
done
printf '%s' "$cur" > "$sig"
awk -F'\t' -v kf="$killed" 'BEGIN{while((getline l < kf)>0) k[l]=1} !($1 in k)' "$m"
POLL
        # kill.sh: delete the selected zellij session on the host (force-kills a live one) and
        # record it in $killed so the list drops it immediately.
        cat > "$killsh" <<'KILL'
#!/bin/sh
host=$1 s=$2 killed=$3
ssh "$host" zellij delete-session --force "$s" >/dev/null 2>&1 && printf '%s\n' "$s" >> "$killed"
KILL
        ssh::durable::stream_supervisor "$host" "$mirror" "$done" "$req" "$quit" "$pidf" "$autherr" "$statusf" &
        local sup=$!

        # Wait briefly for the first snapshot before showing fzf (≤15s; $done means no sessions).
        local t=0
        while [[ ! -s $mirror && ! -f $done ]]; do sleep 0.1; (( ++t > 150 )) && break; done

        local hdr='enter: attach · ctrl-r: re-summarise · ctrl-x: kill · esc: new session'
        local chosen='' pick=1
        if [[ -s $mirror ]]; then
            local preview="ssh ${(q)host} sh -s -- --preview {1} ${(q)host} < ${(q)rscript}"
            # start: show the cached snapshot at once. load: wait for the next real mirror change
            # (debounced — see poll.sh) then reload, swap the header to the auth error if one lands,
            # and unbind once $done is set. ctrl-r: force a fresh re-summarise. ctrl-x: kill the
            # selected session (confirm prompt). All displays go through show.sh (killed-filtered).
            chosen=$(fzf < /dev/null \
                --ansi --delimiter=$'\t' --with-nth=2 \
                --prompt="durable@${host}> " \
                --header="$hdr" \
                --height=90% --border --reverse \
                --preview "$preview" --preview-window='right:62%:wrap' \
                --bind "start:reload(sh $show $mirror $killed)" \
                --bind "load:transform-header[test -s $autherr && cat $autherr || { test -s $statusf && printf '%s · %s' \"\$(cat $statusf)\" '$hdr' || echo '$hdr'; }]+transform[test -f $done && echo 'reload(sh $show $mirror $killed)+unbind(load)' || echo 'reload(sh $poll $mirror $done $sig $killed)']" \
                --bind "ctrl-r:execute-silent(command rm -f $done $autherr $sig; : > $req)+rebind(load)+reload(sh $show $mirror $killed)" \
                --bind "ctrl-x:execute-silent(sh $killsh ${(q)host} {1} $killed)+reload(sh $show $mirror $killed)")
            pick=$?
        fi

        # Teardown: stop the supervisor + any in-flight refresh, drop the tmp dir (keep any
        # auth-failure message so we can surface it after fzf closes).
        : > "$quit"
        [[ -s $pidf ]] && kill "$(<$pidf)" 2>/dev/null
        kill "$sup" 2>/dev/null
        local authmsg=''; [[ -s $autherr ]] && authmsg=$(<$autherr)
        command rm -f "$mirror" "$mirror.tmp" "$done" "$req" "$quit" "$pidf" "$autherr" "$sig" "$poll" \
            "$statusf" "$killed" "$show" "$killsh"
        rmdir "$tmpd" 2>/dev/null
        [[ -n $authmsg ]] && print -u2 -- "ssh::durable: ⚠ $authmsg"

        # Reap is opt-in only (ssh::durable <host> --reap). Auto-firing it on every teardown could
        # kill mosh-servers whose live-client detection raced at teardown — dropping tabs that were
        # actually still attached. The green ● is computed fresh on each open (compute_connf), so it
        # never depended on this reap.

        if [[ $pick -eq 0 && -n $chosen ]]; then
            ssh::durable::attach "$host" "${chosen%%$'\t'*}" "$@"
            return
        fi
        # Esc / no pick → fall through to a fresh session.
    fi

    ssh::durable::fresh "$host" "$@"
}

# zellij::sweep-husks [--dry-run]
#
# Close LOCAL cmux zellij sessions that are idle husks (pane running only a bare shell). These
# pile up from durable hops that strand a detached local zellij (now auto-deleted on hop — see
# auto-attach.zsh — but legacy ones, cmux surface re-mints, and aborted hops still accumulate).
#
# "Doing something" is judged by the session's pane PROCESSES, not screen text: `zellij action
# dump-screen` is unreliable here (full-screen TUIs like claude/vim live on the alternate screen
# so it dumps blank, and `-s` targeting of detached sessions returns nothing). The server process
# names its session in its cmdline (`zellij --server <sock>/<session>`), so we map session ->
# server PID -> descendant processes and keep any session running a real foreground process
# (claude, mosh-client, ssh, vim, a build, …). The current session is always kept.
zellij::sweep-husks() {
    emulate -L zsh
    local dry=0; [[ "$1" == (--dry-run|-n) ]] && dry=1
    local agent="$ZELLIJ_SESSION_NAME" snap; snap=$(ps -axww -o pid,ppid,command)
    local spid rest sess meaningful
    ps -axww -o pid,command | grep 'zellij --server' | grep -v grep | while read -r spid rest; do
        sess=$(print -r -- "$rest" | grep -oE 'cmux-[a-z0-9-]+$'); [[ -z $sess ]] && continue
        [[ $sess == $agent ]] && { print -r -- "  keep(current) $sess"; continue }
        meaningful=$(print -r -- "$snap" | awk -v root="$spid" '
            { par[$1]=$2; c=$0; sub(/^ *[0-9]+ +[0-9]+ +/,"",c); cmdof[$1]=c }
            END{ q[root]=1; ch=1; while(ch){ch=0; for(p in par){if(q[par[p]]&&!q[p]){q[p]=1;ch=1}}}
              for(p in par){ if(q[p]&&p!=root){ c=cmdof[p]
                if(c ~ /^(\/[^ ]*\/)?zellij( |$)/) continue
                if(c ~ /^(\/usr\/bin\/|\/bin\/)?-?(zsh|bash|sh|login)( |$)/) continue
                if(c ~ /snapshot-zsh.*eval/ || c ~ /(ps -axww|ps -ao ppid|[ \/]awk |sed -|grep |head -|caffeinate)/) continue
                print c } } }')
        if [[ -n $meaningful ]]; then
            print -r -- "  keep(active)  $sess  [${$(print -r -- "$meaningful" | head -1)[1,60]}]"
        elif (( dry )); then
            print -r -- "  idle→kill     $sess"
        else
            # Kill the server PID directly, NOT `zellij delete-session` — when husks have piled up
            # (zellij 0.44.3 spawns a `ps -ao ppid,args` per server; at scale they wedge the macOS
            # proc table in uninterruptible state), the zellij CLI itself hangs, so delete-session
            # would block on the exact failure this is meant to clear. SIGTERM stops the server (and
            # its ps storm); the EXITED entry is cosmetic and zellij prunes it.
            kill "$spid" 2>/dev/null && print -r -- "  killed idle   $sess"
        fi
    done
}
