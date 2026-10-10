#!/usr/bin/env bash
# Hook (Stop): hold the final reply to the house prose rules before the turn ends.
#
# Stop is the only event that can reopen a finished turn: its input carries the
# final text as last_assistant_message, and exiting 2 hands stderr back to Claude
# as the reason to continue. The gate strips code (fenced blocks and inline
# spans), runs the prose-conventions checker on the prose that is left, asks a
# small model which hits are real, and returns those as a rewrite instruction.
# The reply already on screen stays where it is; the rewrite lands beneath it.
# Rewrites are capped per prompt so a rule that misfires cannot loop a session.
#
#   checker   modules/agents/skills/prose-conventions/prose-lint.sh
#   judge     claude -p --model haiku with response-gate-judge.md (skipped without claude;
#             fails "Not logged in" wherever claude authenticates from env, since
#             Claude Code strips its credential vars from hook processes)
#   state     $XDG_STATE_HOME/claude-response-gate/<session_id>.state  "<prompt_id> <rewrites>"
#   log       $XDG_STATE_HOME/claude-response-gate/gate.log  (hits, judge drops and reasons)
#   off       CLAUDE_RESPONSE_GATE=0      cap: CLAUDE_RESPONSE_GATE_MAX (default 1)
#             CLAUDE_RESPONSE_GATE_JUDGE=0  regex hits only, no judge
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
# A reply that is one JSON document is structured output (pr-reviewer's verdict),
# not prose: a rewrite can only break the shape a reader parses.
jq -e 'type == "object" or type == "array"' <<<"$reply" >/dev/null 2>&1 && exit 0

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

# Fenced blocks and inline spans are code; the rules are about prose. Fences go
# entirely; an inline span becomes the word `codespan` rather than nothing, so
# the sentence around it keeps its shape ("the tarball is `x`." deleted to
# "the tarball is ." reads as a stranded auxiliary). The checker runs from the
# temp dir on a bare filename so its location column reads `reply.md:N`, which
# becomes `line N` below.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
# shellcheck disable=SC2016  # the backticks are literal markdown, not a subshell
awk '/^[[:space:]]*(```|~~~)/ {fence = !fence; next} !fence' <<<"$reply" |
  sed -E 's/`[^`]*`/codespan/g' >"$tmp/reply.md"
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

# Matches whose literal or technical sense is the common one in an engineering
# reply, so only a reader of the context can tell the tic: "the robust tier" names
# a property where "a robust solution" is the banned intensifier, "a lasting
# refusal" is a state, "an underscore" is a character, Swift is a language, "read
# literally" is the plain adverb, "marks an import as guarded" and "each row
# represents a run" are the literal verbs. These stand only when the judge calls
# them real. Replaying the gantry fleet's 137 gated replies (2026-10-09/10), every
# robust, lasting, underscore, literally and marks hit was a misfire; swift,
# highlight and represents have the same split between a literal and a tic sense.
contextual_re='^\[banned-vocab\] +"(robust|lasting|underscore|swift|highlight)"'
contextual_re+='|^\[copula-avoidance\] +"(marks|represents) |^\[unnecessary-word\] +"literally"'
drop_contextual() {
  local hit kept=()
  for hit in "${hits[@]}"; do
    if [[ "${hit,,}" =~ $contextual_re ]]; then
      printf '%s\t%s\t  unjudged, dropped: %s\n' "$(stamp)" "${sid:0:8}" "$hit" >>"$log"
    else
      kept+=("$hit")
    fi
  done
  hits=("${kept[@]+"${kept[@]}"}")
}

# The regexes are the recall stage and over-match: a quoted example, a plain
# list of steps, or markdown structure all look like the tic they hunt. A small
# model reads each hit in the context of the whole reply and keeps only the
# real ones. --restricted ignores the user's settings files, so the judge's own
# session runs no hooks (CLAUDE_RESPONSE_GATE=0 backs that up). `timeout` execs
# the claude on PATH, so no shell-function wrapper gets in; it cannot run the
# `command` builtin either, which is why the judge is not wrapped in it.
# The reply and hits are appended rather than substituted into placeholders:
# bash 5.2 expands `&` in a ${x/pat/rep} replacement to the matched text.
# A judge that fails or answers malformed JSON returns 1 and leaves every hit
# for the caller, which keeps all but the contextual ones; the log says so.
judge_hits() {
  local listing="" i prompt verdicts
  for i in "${!hits[@]}"; do listing+="$((i + 1)). ${hits[$i]}"$'\n'; done
  prompt="$(<"$judge_prompt")"$'\n\n<reply>\n'"$reply"$'\n</reply>\n\n<hits>\n'"$listing"'</hits>'
  (cd "$tmp" && CLAUDE_RESPONSE_GATE=0 timeout 60 claude -p --restricted \
    --tools "" --model haiku --no-session-persistence --output-format json \
    --json-schema "$judge_schema" "$prompt" >"$tmp/judge.out" 2>"$tmp/judge.err")
  # The CLI reports an API or auth failure inside its JSON (terminal_reason,
  # result) with an empty stderr, so the log carries both.
  if ! verdicts=$(jq -ec '.structured_output.verdicts | arrays' "$tmp/judge.out" 2>/dev/null); then
    printf '%s\t%s\tjudge failed on %s hit(s): %s %s\n' "$(stamp)" "${sid:0:8}" \
      "${#hits[@]}" "$(jq -rj '"\(.terminal_reason // "") \(.result // "")"' "$tmp/judge.out" \
        2>/dev/null | head -c 200)" "$(head -c 200 "$tmp/judge.err" | tr '\n' ' ')" >>"$log"
    return 1
  fi
  jq -r '.[] | select(.real == false) | "\(.hit)\t\(.reason)"' <<<"$verdicts" |
    while IFS=$'\t' read -r i reason; do
      printf '%s\t%s\t  dropped: %s  (%s)\n' "$(stamp)" "${sid:0:8}" \
        "${hits[$((i - 1))]:-?}" "$reason" >>"$log"
    done
  # A hit with no verdict stays: only an explicit "not real" drops one.
  local kept=()
  while read -r i; do kept+=("${hits[$((i - 1))]}"); done < <(jq -r --argjson n "${#hits[@]}" \
    '[.[] | select(.real == false) | .hit] as $drop
     | range(1; $n + 1) | select(. as $i | ($drop | map(. == $i) | any) | not)' <<<"$verdicts")
  hits=("${kept[@]+"${kept[@]}"}")
}

judge_prompt="$(dirname "${BASH_SOURCE[0]}")/response-gate-judge.md"
judge_schema='{"type":"object","required":["verdicts"],"properties":{"verdicts":{"type":"array",
"items":{"type":"object","required":["hit","real","reason"],"properties":{"hit":{"type":"integer"},
"real":{"type":"boolean"},"reason":{"type":"string"}}}}}}'
judged=0
if [[ "${CLAUDE_RESPONSE_GATE_JUDGE:-1}" != 0 && -f "$judge_prompt" ]] && command -v claude >/dev/null; then
  judge_hits && judged=1
fi
((judged)) || drop_contextual
((${#hits[@]} > 0)) || exit 0

printf '%s %s\n' "$pid" "$((rewrites + 1))" >"$state"
printf '%s\t%s\trewrite %s: %s\n' "$(stamp)" "${sid:0:8}" "$((rewrites + 1))" \
  "$(printf '%s\n' "${hits[@]}" | grep -o '^\[[^]]*\]' | sort -u | tr '\n' ' ')" >>"$log"
# The matched text, one line per hit, so a misfiring rule can be judged later.
for hit in "${hits[@]}"; do
  printf '%s\t%s\t  hit: %s\n' "$(stamp)" "${sid:0:8}" "$hit" >>"$log"
done

{
  printf 'Your reply broke the house prose rules (the prose-conventions skill). Each hit shows the rule, the matched text in quotes, the line around it, and its line number in the reply:\n\n'
  printf '  %s\n' "${hits[@]:0:20}"
  ((${#hits[@]} > 20)) && printf '  ... and %d more\n' $((${#hits[@]} - 20))
  printf '\nRewrite the whole reply so it passes and send only the rewrite, with no apology\n'
  printf 'and no note about the edit. Code spans and fenced blocks are exempt, so a term you\n'
  printf 'are deliberately quoting can go in backticks. If a rule misfired, say so in one\n'
  printf 'plain sentence rather than contorting the reply.\n'
} >&2
exit 2
