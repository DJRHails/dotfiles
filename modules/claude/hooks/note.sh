#!/usr/bin/env bash
# Hook (UserPromptSubmit): handle `/note` entirely in the shell.
#
#   /note <text>   pin <text> to the status line
#   /note          clear it
#
# The hook sees the raw prompt before slash-command expansion and blocks it, so
# the note never reaches the model: no turn, no tokens. Verified with
# `claude -p "/note x" --output-format json`, which reports num_turns 0 and
# cost 0, with or without a commands/note.md present. The status line
# (scripts/statusline.sh) shows the file on its next refresh, and
# modules/agents/commands/note.md exists only so `/note` is in the menu.
#
#   ${TMPDIR:-/tmp}/claude-note-<session_id>.txt   the pinned note
set -euo pipefail

input=$(cat)
prompt=$(jq -r '.prompt // empty' <<<"$input")

case "$prompt" in
/note | /note[[:space:]]*) ;;
*) exit 0 ;;
esac

sid=$(jq -r '.session_id // empty' <<<"$input")
[[ -n "$sid" ]] || exit 0
note_file="${TMPDIR:-/tmp}/claude-note-${sid}.txt"

# One line: the status line has no second row to spare, and a tab would break
# its column alignment.
note=$(printf '%s' "${prompt#/note}" | tr '\n\t' '  ' | sed -e 's/^ *//' -e 's/ *$//')

if [[ -z "$note" ]]; then
  rm -f "$note_file"
  msg="note cleared"
else
  printf '%s' "$note" >"$note_file"
  msg="note: ${note}"
fi

# suppressOriginalPrompt stops the block message echoing the prompt back.
jq -cn --arg r "$msg" '{decision: "block", reason: $r,
  hookSpecificOutput: {hookEventName: "UserPromptSubmit", suppressOriginalPrompt: true}}'
