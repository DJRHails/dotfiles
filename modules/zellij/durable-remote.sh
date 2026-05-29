#!/bin/sh
# Emit one tab-separated line per live zellij session:
#   <session-name>\t<short-id>  —  <one-line summary of what the panel is doing>
#
# Runs entirely on the host (single ssh): dumps + summaries are local, summaries are
# cached under ~/.cache/durable-summaries and refreshed when older than <ttl> seconds.
# Concurrency is bounded so we stay gentle on the box and under sshd MaxSessions.
#
# args: 1=host-prefix-to-strip  2=model  3=ttl-seconds  4=max-parallel
set -u
hostpfx="${1:-}"; model="${2:-claude-haiku-4-5}"; ttl="${3:-300}"; par="${4:-6}"
cdir="$HOME/.cache/durable-summaries"; mkdir -p "$cdir"
prompt='This is the current terminal screen of a dev session. In ONE terse line (max 12 words), say what it is currently doing. No preamble.'
now=$(date +%s)

sessions=$(zellij list-sessions 2>/dev/null \
  | sed -E 's/\x1b\[[0-9;]*m//g' \
  | grep -v 'EXITED' \
  | awk 'NF {print $1}')
[ -n "$sessions" ] || exit 0

summarise() {  # $1=session  $2=cachefile
  zellij -s "$1" action dump-screen 2>/dev/null \
    | grep -v '^[[:space:]]*$' | tail -n 40 \
    | { if command -v timeout >/dev/null 2>&1; then timeout 60 claude -p --model "$model" "$prompt"
        else claude -p --model "$model" "$prompt"; fi; } 2>/dev/null \
    | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//' | cut -c1-90 > "$2.tmp" 2>/dev/null
  if [ -s "$2.tmp" ]; then mv -f "$2.tmp" "$2"; else rm -f "$2.tmp"; fi
}

# Refresh stale/missing summaries, bounded to $par concurrent (drain every $par launches).
i=0
for s in $sessions; do
  f="$cdir/$s"; mt=0
  [ -f "$f" ] && mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [ ! -s "$f" ] || [ $((now - mt)) -gt "$ttl" ]; then
    summarise "$s" "$f" &
    i=$((i + 1))
    [ $((i % par)) -eq 0 ] && wait
  fi
done
wait

# Emit the menu from cache.
for s in $sessions; do
  sum='?'
  [ -s "$cdir/$s" ] && sum=$(cat "$cdir/$s")
  printf '%s\t%s  —  %s\n' "$s" "${s#cmux-"${hostpfx}"-}" "$sum"
done
