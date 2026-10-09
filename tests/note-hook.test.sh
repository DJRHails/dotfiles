#!/usr/bin/env bash
# Behavior suite for modules/claude/hooks/note.sh (UserPromptSubmit).
# Self-contained: `bash tests/note-hook.test.sh`. Exits non-zero on failure.
#
# Both directions are pinned. A `/note` that slips through costs a model turn and
# puts the note in the transcript instead of the status line; a false match
# blocks an ordinary prompt that merely mentions /note.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
hook="$repo_root/modules/claude/hooks/note.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
# The hook and the status line agree on ${TMPDIR:-/tmp} for the note file.
export TMPDIR="$work"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

# event <prompt> [session_id] — the hook's stdin for that prompt.
event() { jq -cn --arg p "$1" --arg s "${2-sess1}" '{prompt: $p, session_id: $s, cwd: "/x"}'; }
# run <prompt> [session_id] — stdout of the hook; its exit status is the hook's,
# so `out=$(run …); rc=$?` captures both.
run() { event "$@" | bash "$hook" 2>"$work/err"; }
note_file="$work/claude-note-sess1.txt"

# -- pin ----------------------------------------------------------------------
out=$(run '/note hello world')
rc=$?
check pin-exit "0" "$rc"
check pin-blocks "block" "$(jq -r .decision <<<"$out")"
check pin-reason "note: hello world" "$(jq -r .reason <<<"$out")"
check pin-suppresses-echo "true" "$(jq -r .hookSpecificOutput.suppressOriginalPrompt <<<"$out")"
check pin-event-name "UserPromptSubmit" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")"
check pin-file "hello world" "$(cat "$note_file")"
check pin-no-stderr "" "$(cat "$work/err")"

# -- replace, with whitespace and newlines collapsed to one line ---------------
out=$(run $'/note   two\nlines\there  ')
check replace-file "two lines here" "$(cat "$note_file")"
check replace-reason "note: two lines here" "$(jq -r .reason <<<"$out")"

# -- quotes survive the JSON round trip ------------------------------------------
out=$(run '/note say "hi" to <them> & co')
check quotes-file 'say "hi" to <them> & co' "$(cat "$note_file")"
check quotes-reason 'note: say "hi" to <them> & co' "$(jq -r .reason <<<"$out")"

# -- clear ----------------------------------------------------------------------
out=$(run '/note')
rc=$?
check clear-exit "0" "$rc"
check clear-reason "note cleared" "$(jq -r .reason <<<"$out")"
check clear-removes-file "1" "$([ -e "$note_file" ] && echo 0 || echo 1)"
run '/note again' >/dev/null
out=$(run '/note   ')
check clear-trailing-spaces "note cleared" "$(jq -r .reason <<<"$out")"
check clear-trailing-spaces-file "1" "$([ -e "$note_file" ] && echo 0 || echo 1)"

# -- per-session files -------------------------------------------------------------
run '/note for one' sess1 >/dev/null
run '/note for two' sess2 >/dev/null
check session-one "for one" "$(cat "$work/claude-note-sess1.txt")"
check session-two "for two" "$(cat "$work/claude-note-sess2.txt")"

# -- anything that is not the command passes through untouched --------------------
for prompt in '/notes please' 'hello /note' 'note this' '/not e' ' /note x' 'Add /note to the dotfiles'; do
  out=$(run "$prompt" sess3)
  rc=$?
  check "passthrough-exit[$prompt]" "0" "$rc"
  check "passthrough-silent[$prompt]" "" "$out"
done
check passthrough-no-file "1" "$([ -e "$work/claude-note-sess3.txt" ] && echo 0 || echo 1)"

# -- no session id: nothing to key the file on, so stay out of the way -------------
out=$(jq -cn '{prompt: "/note x"}' | bash "$hook")
check no-session-exit "0" "$?"
check no-session-silent "" "$out"

if ((fails == 0)); then
  printf 'all passed\n'
  exit 0
fi
printf '%s failed\n' "$fails"
exit 1
