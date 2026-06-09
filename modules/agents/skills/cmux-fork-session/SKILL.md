---
name: cmux-fork-session
description: "Fork the current Claude Code session into a new cmux split pane (or tab) — opens a split beside the caller, resumes this session with --fork-session, titles it 'fork: <name>', and keeps that title. Use when the user asks to fork/duplicate/branch the current session into a new split or tab. Works whether the session is local on the cmux UI host or running on a durable/mosh remote (e.g. bonbon). Requires the macOS cmux app on the UI host — skip if the session was not started from cmux."
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
   `CLAUDE_CONFIG_DIR`. Reads the session **name** from the sessions JSON. The **live
   surface id** is then resolved on a remote by matching that name against the cmux
   surface *titles* (`cmux tree --all`): the Stop-hook titler propagates the session
   name out as the terminal title (Claude session → zellij/mosh → cmux surface title),
   so the surface whose title contains the name is this one. That key is the only one
   that is **focus-independent** and survives cmux re-minting UUIDs across app restarts
   — unlike the forwarded `CMUX_SURFACE_ID` / the live-ids sidecar (both go stale → the
   old "Workspace not found"), and unlike "focused" (drifts between tabs). Locally the
   freshly-injected `CMUX_SURFACE_ID` is trusted directly. The resolved id also heals
   the sidecar so `cmux-session-tab` recovers too.
2. Reads the session **name** and project **cwd** from the matching
   `$CLAUDE_CONFIG_DIR/sessions/<pid>.json`.
3. Opens a split beside the caller via `cmux rpc surface.split` (or a tab via
   `surface.create`), launches the fork via `surface.send_text`, and titles it via
   `tab.action`. Each call goes through a `run_cmux` shim: on the cmux UI host it hits
   the local app socket directly; on a remote it ssh'es to the app host
   (`CMUX_APP_HOST`, default `trifle`) and runs *its* cmux against *its* socket, args
   base64-encoded per-arg so the JSON survives ssh re-quoting.
4. Launches the fork — `cd <cwd> && <launcher> --resume <id> --fork-session` — picking
   the launcher that matches the session's config dir: `~/.claude-ant` → `claude::ant`
   (sources `.env.ant` auth + ensure step), `~/.claude` → `claude`, anything else
   → `CLAUDE_CONFIG_DIR=<cfg> claude`. Matching the wrapper matters — a bare
   `CLAUDE_CONFIG_DIR=… claude` skips `claude::ant`'s auth and lands "Not logged in".
5. Titles the new tab `fork: <name>` (`rpc tab.action`).
6. Pre-seeds the fork's tab-sync hook state so its first turn doesn't overwrite the
   `fork:` title with the inherited name (see the `Stop` hook `sync-cmux-tab.sh`).

## Local vs remote — two transports, one extra hop

All cmux mutations use `cmux rpc <method>` (`surface.split` / `surface.create` /
`surface.send_text` / `tab.action`) — `rpc` over the high-level verbs because it
passes any server method straight through. The mode is decided by whether the cmux
app binary exists on this host (`/Applications/cmux.app/.../bin/cmux`):

- **Local** (on the cmux UI host): `run_cmux` hits the local app socket; the new
  surface is a shell on the same machine, so the fork is just `cd <cwd> && <launcher>
  --resume … --fork-session` sent straight to it.
- **Remote** (durable/mosh, e.g. `bonbon`): `run_cmux` ssh'es to the app host. But the
  split creates a fresh shell *on the mac*, while the session's cwd + `claude` live on
  the remote — so a bare `cd` would fail (this was the "didn't ssh into bonbon" bug).
  Instead the script (running on the remote) writes a one-pane zellij **layout** that
  launches the fork, then drives the mac surface to `mosh <remote> -- zellij
  --new-session-with-layout <layout> --session <forksess>` (the `--session …/--layout`
  pair *attaches* and errors if absent — `--new-session-with-layout` is what *creates*).
  Because the split's login shell needs a beat to reach a prompt (input typed too early
  is dropped), the send is **retried until the session actually comes up** — the script
  runs on the fork's own host, so a local `zellij list-sessions` is the authoritative
  readiness check, and it re-checks before each resend so the hop is never typed into an
  already-attached mosh pane. The fork lands in its own **durable zellij session**, and
  its live-id sidecar is written so it's controllable via `cmux-session-tab` afterwards.

The `zsh -lc` outer hop (login, non-interactive) gets PATH but does **not** source
`.zshrc`, so `auto-attach.zsh` doesn't fire and fight the explicit attach; the layout
pane's `zsh -ic` is interactive so `claude::ant` resolves, and auto-attach there
no-ops because `$ZELLIJ` is already set. Override the remote host with
`CMUX_DURABLE_HOST` and the app host with `CMUX_APP_HOST` if the defaults are wrong.

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
