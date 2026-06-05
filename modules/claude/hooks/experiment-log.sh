#!/bin/bash
set -euo pipefail
# Hook (Stop): keep a project's EXPERIMENT_LOG.md current when the agent finishes
# a turn, via a two-stage LLM pipeline.
#
#   1. Haiku DRAFTS a terse entry from THIS turn — the transcript segment appended
#      since the previous agent-end (Stop), with injected skill/command/system
#      turns stripped.
#   2. Opus CURATES: given the log's recent tail + the draft, it decides
#        append  — add a clean standalone entry (rewritten for style),
#        amend   — fold the turn into the most recent entry (only if that entry is
#                  itself auto-generated — never a hand-written one),
#        skip    — drop it as trivial / already covered.
#
# Robust + safe: silent no-op without $cwd/EXPERIMENT_LOG.md; naive last-user /
# last-assistant stub when there's no API key (offline); appends the Haiku draft
# if the Sonnet pass fails; processes only new lines per session (no re-logging);
# never blocks the Stop event.
#
# Config (env): EXPERIMENT_LOG_HOOK_{DRAFT_MODEL,CURATE_MODEL,MAXCHARS,TAILLINES}.
# API key: $ANTHROPIC_API_KEY, else $cwd/.env (ANTHROPIC_API_KEY_BATCH|_LOW_PRIO|plain).

INPUT=$(cat)

STOP_HOOK_ACTIVE=$(jq -r '.stop_hook_active // false' <<<"$INPUT")
[[ "$STOP_HOOK_ACTIVE" == "true" ]] && exit 0

CWD=$(jq -r '.cwd // empty' <<<"$INPUT")
[[ -z "$CWD" ]] && exit 0
LOG="$CWD/EXPERIMENT_LOG.md"
[[ -f "$LOG" ]] || exit 0

SESSION_ID=$(jq -r '.session_id // "unknown"' <<<"$INPUT")
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$INPUT")
[[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || exit 0

DRAFT_MODEL="${EXPERIMENT_LOG_HOOK_DRAFT_MODEL:-claude-haiku-4-5-20251001}"
CURATE_MODEL="${EXPERIMENT_LOG_HOOK_CURATE_MODEL:-claude-opus-4-8}"
MAXCHARS="${EXPERIMENT_LOG_HOOK_MAXCHARS:-16000}"
TAILLINES="${EXPERIMENT_LOG_HOOK_TAILLINES:-1000}"
MARKER="_Auto-curated (haiku → opus)._"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-experiment-log"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$SESSION_ID"

# jq predicate: reject injected/synthetic "user" turns.
INJECTED='def injected: test("Base directory for this skill|<command-name>|<command-message>|<command-args>|<local-command-(stdout|stderr)>|<system-reminder>|Caveat: The messages below were generated|This session is being continued from a previous"; "i");'

# --- This turn's segment: transcript lines appended since the previous Stop. ---
CUR_COUNT=$(awk 'END {print NR}' "$TRANSCRIPT")
RAW_STATE=$(cat "$STATE_FILE" 2>/dev/null || true)
if [[ "$RAW_STATE" =~ ^[0-9]+$ ]]; then
  PREV_COUNT="$RAW_STATE"
else
  PREV_COUNT="" # no (or legacy) state → bootstrap
fi

if [[ -n "$PREV_COUNT" ]]; then
  [[ "$CUR_COUNT" -le "$PREV_COUNT" ]] && exit 0 # nothing new since last agent-end
  START_LINE=$((PREV_COUNT + 1))
else
  # Bootstrap (first hooked turn): start at the last genuine user message.
  START_IDX=$(jq -rs "$INJECTED"'
    def textof: (.message.content) | if type=="string" then . else (map(select(.type=="text")|.text)|join(" ")) end;
    . as $a | ([ range(0;($a|length)) as $i
      | select($a[$i].type=="user" and ($a[$i].isSidechain!=true)
          and (($a[$i]|textof) as $t | $t!=null and $t!="" and ($t|startswith("<")|not) and ($t|injected|not)))
      | $i ] | last) // 0' "$TRANSCRIPT" 2>/dev/null || echo 0)
  START_LINE=$((START_IDX + 1))
fi

SEG=$(sed -n "${START_LINE},\$p" "$TRANSCRIPT")
[[ -n "$SEG" ]] || exit 0

# Render the segment as "role: text" (text blocks + tool markers); drop sidechains
# and injected user turns. This is the only content the summariser sees.
TURN=$(printf '%s' "$SEG" | jq -rs "
  $INJECTED
  def textof: (.message.content)
    | if type==\"string\" then .
      else (map(if .type==\"text\" then .text elif .type==\"tool_use\" then \"[tool:\\(.name)]\" else empty end) | join(\" \")) end;
  [ .[] | select(.isSidechain!=true) | {r:.type, t:textof}
    | select(.t!=null and .t!=\"\")
    | select((.r==\"user\" and (.t|startswith(\"<\")|not) and (.t|injected|not)) or (.r==\"assistant\"))
    | \"\(.r): \(.t)\" ] | join(\"\n\n\")" 2>/dev/null || true)
TURN=$(printf '%s' "$TURN" | head -c "$MAXCHARS")

collapse() { tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'; }
trim() { # <text> [limit]
  local t="$1" n="${2:-280}"
  if [[ ${#t} -gt $n ]]; then
    printf '%s…' "$(printf '%s' "${t:0:$n}" | sed 's/ [^ ]*$//')"
  else printf '%s' "$t"; fi
}
USER_MSG=$(printf '%s' "$SEG" | jq -rs "$INJECTED"'
  [ .[] | select(.type=="user" and (.isSidechain != true)) | (.message.content)
    | if type=="string" then . else (map(select(.type=="text")|.text)|join(" ")) end
    | select(. != null and (. != "") and (startswith("<")|not) and (injected|not)) ] | last // ""' \
  2>/dev/null | collapse || true)
ASSISTANT_MSG=$(printf '%s' "$SEG" | jq -rs '
  [ .[] | select(.type=="assistant" and (.isSidechain != true)) | (.message.content)
    | if type=="string" then . else (map(select(.type=="text")|.text)|join(" ")) end
    | select(. != null and (. != "")) ] | last // ""' \
  2>/dev/null | collapse || true)

save_state() { printf '%s' "$CUR_COUNT" >"$STATE_FILE"; }

resolve_key() {
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    printf '%s' "$ANTHROPIC_API_KEY"
    return 0
  fi
  local env_file="$CWD/.env" name val
  [[ -f "$env_file" ]] || return 1
  for name in ANTHROPIC_API_KEY_BATCH ANTHROPIC_API_KEY_LOW_PRIO ANTHROPIC_API_KEY; do
    val=$(sed -n "s/^${name}=//p" "$env_file" 2>/dev/null | head -1 | tr -d '"'"'"' ')
    [[ -n "$val" ]] && {
      printf '%s' "$val"
      return 0
    }
  done
  return 1
}
KEY=$(resolve_key || true)

# anthropic_call <model> <system> <user> <max_tokens> -> text (empty on failure).
# No assistant prefill — the newest models (e.g. opus-4-8) reject it.
anthropic_call() {
  local req
  req=$(jq -n --arg m "$1" --arg s "$2" --arg u "$3" --argjson mt "$4" \
    '{model:$m, max_tokens:$mt, system:$s, messages:[{role:"user", content:$u}]}')
  curl -sS --max-time 30 https://api.anthropic.com/v1/messages \
    -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
    -d "$req" 2>/dev/null |
    jq -r '[.content[]? | select(.type=="text") | .text] | join("")' 2>/dev/null || true
}

# extract_json: print the {...} object from possibly-fenced/prefixed model text.
extract_json() {
  awk '
    { buf = buf $0 "\n" }
    END {
      s = index(buf, "{"); if (s == 0) exit
      for (i = length(buf); i > 0; i--) if (substr(buf, i, 1) == "}") { e = i; break }
      if (e > s) printf "%s", substr(buf, s, e - s + 1)
    }'
}

write_entry() { # <title> <body>
  local stamp
  stamp=$(date '+%Y-%m-%d %H:%M')
  {
    printf '\n## %s — %s\n\n' "$stamp" "$1"
    printf '%s\n\n' "$MARKER"
    printf '%s\n' "$2"
  } >>"$LOG"
}

# --- Stage 1: Haiku draft ---
SYS_DRAFT='You write a DETAILED, operational lab-notebook draft for ONE work turn. The input is the turn transcript (a user request, then the assistant'"'"'s actions and final reply, with [tool:Name] markers for tool calls). Capture what actually happened, blow-by-blow and warts-and-all: the request/intent; concrete actions (files created/edited with paths, commands run, key code/config/prompt changes); decisions and the reasoning behind them; bugs, errors, dead-ends and how they were resolved; results and measurements (numbers, AUROCs, pass/fail); and anything left open. Be specific — paths, flags, identifiers, error messages, figures. Output Markdown: line 1 a short title (max 70 chars, no leading "#"), then a blank line, then as many "- " bullets as the work needs (sub-bullets allowed). Prefer completeness over brevity here; a later pass will distil it. No preamble, no sign-off.'

DRAFT=""
[[ -n "$KEY" && -n "$TURN" ]] && DRAFT=$(anthropic_call "$DRAFT_MODEL" "$SYS_DRAFT" "$TURN" 1500)

# No draft (no API key, or the summariser call failed/returned empty — e.g.
# rate-limited during a heavy sweep): skip silently. Emitting a naive stub here
# produced low-value "Auto-stub" entries that had to be cleaned up by hand;
# recording nothing is better than recording junk. State still advances so the
# turn isn't reprocessed on the next Stop.
if [[ -z "$DRAFT" ]]; then
  save_state
  exit 0
fi

# --- Stage 2: Sonnet curation ---
SYS_CURATE='You are the editor of a project EXPERIMENT_LOG.md (a durable lab notebook). You are given the log'"'"'s recent tail and a DETAILED, operational DRAFT of the latest work turn. Distil the draft into a DISTINCTIVE entry that keeps only what is worth remembering weeks later — decisions and their rationale, non-obvious findings, results/numbers, gotchas, dead-ends, and open threads — and drops routine mechanics, restated context, tool-by-tool narration, and noise. Tighter and more selective than the draft; signal over completeness. Return ONLY a JSON object: {"action":"append"|"amend"|"skip","title":"<=70 chars, states the finding","body":"2-5 tight \"- \" bullets (sub-bullets ok)"}.
- "append": a distinct, log-worthy unit → a clean standalone entry in the notebook'"'"'s terse style.
- "amend": directly continues the work in the MOST RECENT entry AND that entry is auto-generated (body preceded by a line starting "_Auto-") → return a rewritten, consolidated version of that entry folding in this turn, so the log keeps one coherent entry instead of fragments. If the most recent entry is hand-written (no "_Auto-" marker), use "append".
- "skip": trivial, redundant, or already covered → title and body "".
Output JSON only, no code fences, no preamble.'

CURATE_INPUT=$(printf '=== RECENT EXPERIMENT_LOG (tail) ===\n%s\n\n=== DRAFT ENTRY FOR LATEST TURN ===\n%s' \
  "$(tail -n "$TAILLINES" "$LOG" | head -c "$MAXCHARS")" "$DRAFT")
DECISION=""
if [[ -n "$KEY" ]]; then
  DECISION=$(anthropic_call "$CURATE_MODEL" "$SYS_CURATE" "$CURATE_INPUT" 800 | extract_json)
fi

ACTION=$(printf '%s' "$DECISION" | jq -r '.action // empty' 2>/dev/null || true)
CTITLE=$(printf '%s' "$DECISION" | jq -r '.title // empty' 2>/dev/null || true)
CBODY=$(printf '%s' "$DECISION" | jq -r '.body // empty' 2>/dev/null || true)

# Curation unusable → short trimmed entry (never dump the verbose draft).
if [[ -z "$ACTION" || ("$ACTION" != "skip" && -z "$CTITLE") ]]; then
  ACTION="append"
  CTITLE=$(trim "${USER_MSG:-session turn}" 80)
  CBODY=$(printf -- '- Request: %s\n- Outcome: %s' \
    "$(trim "${USER_MSG:-(none captured)}")" "$(trim "${ASSISTANT_MSG:-(none captured)}")")
fi

case "$ACTION" in
skip) : ;; # leave the log unchanged
amend)
  LAST=$(grep -n '^## ' "$LOG" | tail -1 | cut -d: -f1 || true)
  # Only replace the last entry when it is auto-generated; else just append.
  if [[ -n "$LAST" ]] && tail -n +"$LAST" "$LOG" | grep -q '^_Auto-'; then
    head -n "$((LAST - 1))" "$LOG" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba}' >"$LOG.tmp"
    mv "$LOG.tmp" "$LOG"
  fi
  write_entry "$CTITLE" "$CBODY"
  ;;
*) write_entry "$CTITLE" "$CBODY" ;;
esac

save_state
exit 0
