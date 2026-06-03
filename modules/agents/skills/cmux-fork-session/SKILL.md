---
name: cmux-fork-session
description: "Fork the current Claude Code session into a new cmux split pane (or tab) — opens a split beside the caller, resumes this session with --fork-session, titles it 'fork: <name>', and keeps that title. Use when the user asks to fork/duplicate/branch the current session into a new split or tab. Works whether the session is local or running on a remote cmux relay host."
---

# cmux: fork this session into a new split (or tab)

Forks the **current** Claude Code session into a **new cmux split pane** (or tab) so
you can branch the conversation and keep working in both, side by side. The new
surface runs `claude --resume <id> --fork-session` (a *new* session id, same history
up to the fork point), is titled `fork: <session-name>`, and that title is kept.

## Usage

Run the reference script — it reads everything from the environment:

```bash
bash .../cmux-fork-session/reference/fork-session.sh                 # split right, title "fork: <name>"
bash .../cmux-fork-session/reference/fork-session.sh "branch: " down # split downward, custom prefix
bash .../cmux-fork-session/reference/fork-session.sh "fork: " tab    # new tab instead of a split
```

Second arg `where`: `right` (default) | `left` | `up` | `down` for a split, or `tab`
for a sibling tab. (The skill base directory is printed when the skill loads.)

## What it does

1. Resolves context from env (no process-tree guessing): `CLAUDE_CODE_SESSION_ID`,
   `CLAUDE_CONFIG_DIR`, `CMUX_SURFACE_ID`, `CMUX_WORKSPACE_ID`.
2. Reads the session **name** and project **cwd** from the matching
   `$CLAUDE_CONFIG_DIR/sessions/<pid>.json`.
3. Opens a split beside the caller via `cmux rpc surface.split` (or a tab via
   `surface.create`), launches the fork via `surface.send_text`, and titles it via
   `tab.action` — all through `rpc` so the path is identical local and remote.
4. Sends `cd <cwd> && <launcher> --resume <id> --fork-session`, picking the
   launcher that matches the session's config dir: `~/.claude-ant` → `claude::ant`
   (sources `.env.ant` auth + ensure step), `~/.claude` → `claude`, anything else
   → `CLAUDE_CONFIG_DIR=<cfg> claude`. Matching the wrapper matters — a bare
   `CLAUDE_CONFIG_DIR=… claude` skips `claude::ant`'s auth and lands "Not logged in".
5. Titles the new tab `fork: <name>` (`cmux rename-tab`).
6. Pre-seeds the fork's tab-sync hook state so its first turn doesn't overwrite the
   `fork:` title with the inherited name (see the `Stop` hook `sync-cmux-tab.sh`).

## Local vs remote — same path

Every cmux mutation goes through `cmux rpc <method>` (`surface.split` /
`surface.create` / `surface.send_text` / `tab.action`). `rpc` is forwarded
identically by the local cmux app and the remote relay, so the **same code path**
works whether the session runs on the cmux UI host or on a remote host (e.g.
`bonbon`). This is why it uses `rpc` rather than the high-level verbs
(`rename-tab`, `new-split`, `identify`, …) — the remote relay CLI exposes only a
subset of those, but `rpc` passes any server method straight through.

Param note: `surface.*` methods target with **`surface_id`**; `tab.action` targets
with **`tab_id`** (passing `surface`/`tab` is silently ignored → acts on the
focused surface).

## Robustness / edge cases

- Not inside cmux, no `cmux`/`jq`, or no `CLAUDE_CODE_SESSION_ID` → clear error, no action.
- Session never `/rename`d (no `.name`) → titles the tab `fork: <session-id>` and
  skips the hook pre-seed (nothing to preserve).
- All cmux writes are best-effort; the fork still launches even if the rename or
  pre-seed step fails.

## Related

- `~/.files/modules/claude/hooks/sync-cmux-tab.sh` — the `Stop` hook that keeps a
  tab's title in step with the session name (macOS `rename-tab`; remote `rpc
  tab.action` with `tab_id`). This script's pre-seed cooperates with it.
