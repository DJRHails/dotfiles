#!/bin/bash
set -euo pipefail
# Hook (Notification): tell me Claude needs attention, with a clickable banner
# that focuses this session's cmux tab.
#
#   - title    = the session's /rename name (resolved from <config>/sessions),
#                else the project dir name.
#   - subtitle = the reason Claude surfaced (the hook's .message).
#   - click    = focus this session's cmux workspace tab (cmux-focus), when the
#                hook fired inside a cmux surface.
#
# Safe + non-blocking: degrades to a plain banner outside cmux or before /rename;
# never fails the Notification event.

INPUT=$(cat)

DOTFILES="${DOTFILES:-$HOME/.files}"
NOTIFY="$DOTFILES/bin/notify"
FOCUS="$DOTFILES/bin/cmux-focus"

MESSAGE=$(jq -r '.message // "Claude needs your attention"' <<<"$INPUT")
SESSION_ID=$(jq -r '.session_id // empty' <<<"$INPUT")
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$INPUT")
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")

# Resolve the session's display name (same source as sync-cmux-tab.sh): the
# sessions file whose .sessionId matches, .name present only after /rename.
NAME=""
if [[ -n "$SESSION_ID" && -n "$TRANSCRIPT" ]]; then
  SESSIONS_DIR="$(dirname "$(dirname "$(dirname "$TRANSCRIPT")")")/sessions"
  [[ -d "$SESSIONS_DIR" ]] && NAME=$(jq -r --arg sid "$SESSION_ID" \
    'select(.sessionId==$sid) | .name // empty' "$SESSIONS_DIR"/*.json 2>/dev/null | head -1)
fi
PROJECT=""
[[ -n "$CWD" ]] && PROJECT=$(basename "$CWD")
TITLE="Claude · ${NAME:-${PROJECT:-Code}}"

# Body carries the project when we have a session name (avoids redundancy).
BODY="$MESSAGE"
[[ -n "$NAME" && -n "$PROJECT" ]] && BODY="$MESSAGE — 📁 $PROJECT"

args=(--title "$TITLE" --subtitle "needs your attention" --message "$BODY" --id "claude-$SESSION_ID")

# Clickable focus only when inside a cmux surface and the helper exists.
if [[ -n "${CMUX_WORKSPACE_ID:-}" && -x "$FOCUS" ]]; then
  args+=(--button "Focus tab" --run "$FOCUS ${CMUX_WORKSPACE_ID}")
fi

"$NOTIFY" "${args[@]}" || true
exit 0
