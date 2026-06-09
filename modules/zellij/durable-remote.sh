#!/bin/sh
# Emit one tab-separated line per live zellij session:
#   <session-name>\t<short-id>  —  <one-line summary of what the panel is doing>
#
# Runs entirely on the host (single ssh): dumps + summaries are local, summaries are
# cached under ~/.cache/durable-summaries and refreshed when older than <ttl> seconds.
# Concurrency is bounded so we stay gentle on the box and under sshd MaxSessions.
#
# Preview mode (`--preview <session>`): print the session's working directory as a
# header, then its live screen. Used by the fzf preview window in ssh::durable.
#
# Progress (`5=1`): emit `DURABLE_TOTAL <n>` then one `DURABLE_TICK` per finished
# summary to stderr, so the caller can draw a progress bar while titling runs. The
# fzf reload path leaves this off (default 0) to keep its stdout-driven list clean.
#
# args: 1=host-prefix-to-strip  2=model  3=ttl-seconds  4=max-parallel  5=progress
set -u

if [ "${1:-}" = "--preview" ]; then
  s="${2:-}"; [ -n "$s" ] || exit 0
  cwd=$(zellij -s "$s" action dump-layout 2>/dev/null \
    | sed -nE 's/^[[:space:]]*cwd "(.*)"$/\1/p' | head -1)
  printf '\033[1;36mcwd:\033[0m %s\n\n' "${cwd:-?}"
  zellij -s "$s" action dump-screen 2>/dev/null | tail -n 200
  exit 0
fi

hostpfx="${1:-}"; model="${2:-claude-haiku-4-5}"; ttl="${3:-300}"; par="${4:-6}"; prog="${5:-0}"
cdir="$HOME/.cache/durable-summaries"; mkdir -p "$cdir"
prompt='This is the current terminal screen of a dev session. In ONE terse line (max 12 words), say what it is currently doing. No preamble.'
now=$(date +%s)

# zellij prints sessions oldest-first; reverse to newest-first in awk (no tac on
# macOS) so the menu — and --query/resurrect, which take the first match — prefer
# the most recent session.
sessions=$(zellij list-sessions 2>/dev/null \
  | sed -E 's/\x1b\[[0-9;]*m//g' \
  | grep -v 'EXITED' \
  | awk 'NF {a[++n] = $1} END {for (i = n; i > 0; i--) print a[i]}')
[ -n "$sessions" ] || exit 0

summarise() {  # $1=session  $2=cachefile
  zellij -s "$1" action dump-screen 2>/dev/null \
    | grep -v '^[[:space:]]*$' | tail -n 40 \
    | { if command -v timeout >/dev/null 2>&1; then timeout 60 claude -p --model "$model" "$prompt"
        else claude -p --model "$model" "$prompt"; fi; } 2>/dev/null \
    | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//' | cut -c1-90 > "$2.tmp" 2>/dev/null
  if [ -s "$2.tmp" ]; then
    mv -f "$2.tmp" "$2"
  else
    rm -f "$2.tmp"
    printf 'durable-remote: summary failed for %s (claude/dump-screen produced nothing)\n' "$1" >&2
  fi
  [ "$prog" = 1 ] && printf 'DURABLE_TICK\n' >&2
}

# Collect stale/missing sessions first so we know how many summaries we'll run.
todo=''; n=0
for s in $sessions; do
  f="$cdir/$s"; mt=0
  [ -f "$f" ] && mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [ ! -s "$f" ] || [ $((now - mt)) -gt "$ttl" ]; then
    todo="$todo $s"; n=$((n + 1))
  fi
done
[ "$prog" = 1 ] && [ "$n" -gt 0 ] && printf 'DURABLE_TOTAL %d\n' "$n" >&2

# Refresh them, bounded to $par concurrent (drain every $par launches).
i=0
for s in $todo; do
  summarise "$s" "$cdir/$s" &
  i=$((i + 1))
  [ $((i % par)) -eq 0 ] && wait
done
wait

# Emit the menu from cache.
for s in $sessions; do
  sum='?'
  [ -s "$cdir/$s" ] && sum=$(cat "$cdir/$s")
  printf '%s\t%s  —  %s\n' "$s" "${s#cmux-"${hostpfx}"-}" "$sum"
done
