#!/usr/bin/env bash
# Hook (Stop): hold the final reply to the house prose rules before the turn ends.
#
# Stop is the only event that can reopen a finished turn: its input carries the
# final text as last_assistant_message, and exiting 2 hands stderr back to Claude
# as the reason to continue. The gate strips code (fenced blocks and inline
# spans), runs the prose-conventions checker on the prose that is left, and
# returns the hits as a rewrite instruction. The reply already on screen stays
# where it is; the rewrite lands beneath it. Rewrites are capped per prompt so a
# rule that misfires cannot loop a session.
#
#   checker   modules/agents/skills/prose-conventions/prose-lint.sh
#   state    $XDG_STATE_HOME/claude-response-gate/<session_id>.state  "<prompt_id> <rewrites>"
#   log       $XDG_STATE_HOME/claude-response-gate/gate.log
#   off       CLAUDE_RESPONSE_GATE=0      cap: CLAUDE_RESPONSE_GATE_MAX (default 1)
#   cost      scripts/response-gate-cost.py <transcript.jsonl> reports the share of a
#             session's tokens that went on gate rewrites
set -uo pipefail

[[ "${CLAUDE_RESPONSE_GATE:-1}" == 0 ]] && exit 0

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../agents/skills/prose-conventions" 2>/dev/null && pwd)"
lint="$skill_dir/prose-lint.sh"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-response-gate"
mkdir -p "$state_dir"
log="$state_dir/gate.log"
stamp() { date +%FT%T%z; }

if [[ ! -f "$lint" ]]; then
  printf '%s\t-\tprose-lint.sh not found at %s; gate inactive\n' "$(stamp)" "$lint" >>"$log"
  exit 0
fi

input=$(cat)
# One jq call per field: a tab-separated `read` collapses empty fields, so a
# missing prompt_id would shift the flag into the wrong variable.
sid=$(jq -r '.session_id // empty' <<<"$input")
pid=$(jq -r '.prompt_id // empty' <<<"$input")
active=$(jq -r '.stop_hook_active // false' <<<"$input")
reply=$(jq -r '.last_assistant_message // ""' <<<"$input")
[[ -n "$sid" && -n "${reply//[[:space:]]/}" ]] || exit 0

# A fresh reply (stop_hook_active false) starts the count over; a continuation
# of the same prompt carries it on. prompt_id can be empty on old builds, in
# which case the flag alone drives it: the state stores `-` in its place, since
# `read` would drop an empty first field and shift the count into it.
pid=${pid:--}
# One rewrite per prompt by default. A rewrite that still fails is a misfiring
# rule more often than bad prose, and every rewrite re-reads the whole context
# and regenerates the reply: measured at about 1.5% of a long session's spend
# for a single rewrite (scripts/response-gate-cost.py).
max=${CLAUDE_RESPONSE_GATE_MAX:-1}
state="$state_dir/${sid}.state"
rewrites=0
if [[ "$active" == true ]] && read -r last_pid last_n <"$state" 2>/dev/null &&
  [[ "$last_pid" == "$pid" && "$last_n" =~ ^[0-9]+$ ]]; then
  rewrites=$last_n
fi
if ((rewrites >= max)); then
  printf '%s\t%s\tgave up after %s rewrite(s)\n' "$(stamp)" "${sid:0:8}" "$rewrites" >>"$log"
  exit 0
fi

# Fenced blocks and inline spans are code; the rules are about prose. The
# checker runs from the temp dir on a bare filename so its location column
# reads `reply.md:N`, which becomes `line N` below.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
# shellcheck disable=SC2016  # the backticks are literal markdown, not a subshell
awk '/^[[:space:]]*(```|~~~)/ {fence = !fence; next} !fence' <<<"$reply" |
  sed -E 's/`[^`]*`//g' >"$tmp/reply.md"
[[ -s "$tmp/reply.md" ]] || exit 0

# Rules the gate does not enforce. Each is a shape heuristic: it matches the
# form of a sentence rather than a banned word, and on a technical reply the
# form is usually earned. The guide's own tricolon rule exempts lists of
# concrete specifics, which no regex can tell from an abstract triad, and a
# false positive here costs a whole turn.
#   rule-of-three   any clause shaped "A, B, and C"
skipped_rules=(rule-of-three)

hits=()
add_hits() {
  local line id
  while IFS= read -r line; do
    [[ "$line" == \[* ]] || continue
    id=${line%%]*}
    id=${id#[}
    [[ " ${skipped_rules[*]} " == *" $id "* ]] && continue
    line=${line//reply.md:/line }
    line=${line%  reply.md}
    hits+=("${line:0:220}")
  done
}
add_hits < <(cd "$tmp" && bash "$lint" reply.md 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

((${#hits[@]} > 0)) || exit 0

printf '%s %s\n' "$pid" "$((rewrites + 1))" >"$state"
printf '%s\t%s\trewrite %s: %s\n' "$(stamp)" "${sid:0:8}" "$((rewrites + 1))" \
  "$(printf '%s\n' "${hits[@]}" | grep -o '^\[[^]]*\]' | sort -u | tr '\n' ' ')" >>"$log"

{
  printf 'Your reply broke the house prose rules (the prose-conventions skill). Each hit shows the rule, the text it matched, and the line of the reply it sits on:\n\n'
  printf '  %s\n' "${hits[@]:0:20}"
  ((${#hits[@]} > 20)) && printf '  ... and %d more\n' $((${#hits[@]} - 20))
  printf '\nRewrite the whole reply so it passes and send only the rewrite, with no apology\n'
  printf 'and no note about the edit. Code spans and fenced blocks are exempt, so a term you\n'
  printf 'are deliberately quoting can go in backticks. If a rule misfired, say so in one\n'
  printf 'plain sentence rather than contorting the reply.\n'
} >&2
exit 2
