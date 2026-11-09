#!/usr/bin/env bash
# SessionStart hook: warn when this shell has lost its macOS login session.
#
# A terminal multiplexer server (zellij, tmux) that outlives a logout — e.g. a
# WindowServer watchdog crash, which logs the user out — keeps the dead login
# session's bootstrap port. Everything started inside it then fails every Mach
# lookup: Keychain (-50 from `security`, gog, gh, git credential helpers),
# getpwuid ("No user exists for uid"), process listing. A running process cannot
# be moved into the new login session, so the only fix is a fresh session.
# Probe once at startup and tell both the user and the model, instead of letting
# the first Keychain-backed command fail with an opaque error.
set -euo pipefail

[[ "$(uname -s)" == Darwin ]] || exit 0
security list-keychains >/dev/null 2>&1 && exit 0

where="${ZELLIJ_SESSION_NAME:+zellij session ${ZELLIJ_SESSION_NAME}}"
where="${where:-this terminal}"

msg="⚠ ${where} has lost the macOS login session (Keychain unreachable)."
msg+=" gog, gh, git-over-ssh and brew will fail here."
msg+=" Fix: open a fresh cmux tab and run \`claude --resume\`."

ctx="STALE LOGIN SESSION: ${where} predates the current macOS login (typically a"
ctx+=" WindowServer crash forced a logout and the multiplexer server survived)."
ctx+=" Every Mach-service lookup fails in this shell: Keychain (OSStatus -50),"
ctx+=" user lookups ('No user exists for uid'), process listing. Expect gog, gh,"
ctx+=" git-over-ssh, brew and anything Keychain-backed to fail; do not misdiagnose"
ctx+=" these as expired credentials or missing auth. Tell the user early and"
ctx+=" recommend restarting via a fresh cmux tab + \`claude --resume\`. Workaround"
ctx+=" for a single command: \`cmux workspace create --cwd <dir> --focus false\`,"
ctx+=" wait for its prompt (\`cmux read-screen\`), then \`cmux send\` the command"
ctx+=" with output redirected to a file you read back."

jq -n --arg msg "$msg" --arg ctx "$ctx" '{
  systemMessage: $msg,
  hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}
}'
