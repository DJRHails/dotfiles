---
name: cmux-fork-session
description: "Fork the current agent session — Claude Code or pi — into a new cmux split pane (or tab): opens a split beside the caller, relaunches this session forked (claude --fork-session / pi --fork), titles it 'fork: <name>', and keeps that title. Use when the user asks to fork/duplicate/branch the current session into a new split or tab. Works whether the session is local on the cmux UI host or running on a durable/mosh remote (e.g. bonbon). Requires the macOS cmux app on the UI host — skip if the session was not started from cmux."
---

# cmux: fork this session into a new split (or tab)

Forks the **current** agent session into a **new cmux split pane** (or tab) so you can
branch the conversation and keep working in both, side by side. The new surface gets a
*new* session id with the same history up to the fork point, is titled
`fork: <session-name>`, and that title is kept.

Both agents are supported; the flavour is autodetected (override with `FORK_AGENT`):

| agent | detected by | fork command |
| --- | --- | --- |
| Claude Code | `CLAUDE_CODE_SESSION_ID` | `claude --resume <id> --fork-session` |
| pi | `PI_CODING_AGENT=true` | `pi --fork <session.jsonl> --provider … --model … --thinking …` |

pi is checked first: when nested (a pi session launched from Claude Code) pi is the
innermost, and is the session the caller is actually talking to.

## Usage

Run the reference script — it reads everything from the environment:

```bash
bash .../cmux-fork-session/reference/fork-session.sh                 # split right, title "fork: <name>"
bash .../cmux-fork-session/reference/fork-session.sh "branch: " down # split downward, custom prefix
bash .../cmux-fork-session/reference/fork-session.sh "fork: " tab    # new tab instead of a split
```

Second arg `where`: `right` (default) | `left` | `up` | `down` for a split, or `tab`
for a sibling tab. (The skill base directory is printed when the skill loads.)

Env overrides: `FORK_AGENT=claude|pi` forces the flavour; `PI_SESSION_DIR` overrides pi's
session store; `CMUX_DURABLE_HOST` / `CMUX_APP_HOST` override the remote and app hosts.

## What it does

1. Resolves context from env (no process-tree guessing): `CLAUDE_CODE_SESSION_ID` +
   `CLAUDE_CONFIG_DIR`, or pi's `PI_SESSION_FILE` / `PI_SESSION_ID`. Reads the session
   **name** from the sessions JSON (Claude) or the last `session_info` entry in the
   session JSONL (pi). The **live
   surface id** is then resolved on a remote by matching that name against the cmux
   surface *titles* (`cmux tree --all`): for Claude the tab-sync hook (sync_cmux_tab.py)
   propagates the session name out as the terminal title (Claude session → zellij/mosh → cmux surface title),
   so the surface whose title contains the name is this one. That key is the only one
   that is **focus-independent** and survives cmux re-minting UUIDs across app restarts
   — unlike the forwarded `CMUX_SURFACE_ID` / the live-ids sidecar (both go stale → the
   old "Workspace not found"), and unlike "focused" (drifts between tabs). **pi has no
   tab-sync hook**, so its surface title never carries the pi session name; the pi path
   matches on `$ZELLIJ_SESSION_NAME` instead, which a durable pane keeps as its title
   because nothing renames it. Locally the
   freshly-injected `CMUX_SURFACE_ID` is trusted directly. The resolved id also heals
   the sidecar so `cmux-session-tab` recovers too.
2. Reads the session **name** and project **cwd** from the matching
   `$CLAUDE_CONFIG_DIR/sessions/<pid>.json` (Claude) or the session JSONL's first
   `session` entry + last `session_info` entry (pi).
3. Opens a split beside the caller via `cmux rpc surface.split` (or a tab via
   `surface.create`), launches the fork via `surface.send_text`, and titles it via
   `tab.action`. Each call goes through `run_cmux`, the shared transport in
   [`cmux-remote.sh`](../../../claude/hooks/lib/cmux-remote.sh) (also used by the rename
   hook, so the two can't drift): on the cmux UI host it execs the local app binary; on a
   remote it ssh'es (`ssh -n`) to the app host (`CMUX_APP_HOST`, default `trifle`) and runs
   *its* cmux there, args base64-encoded per-arg so the JSON survives ssh re-quoting. It
   does **not** force `CMUX_SOCKET_PATH` — cmux auto-discovers its socket (the path moved
   from `~/Library/Application Support/cmux` to `~/.local/state/cmux` in a recent build, so
   the old hardcode broke with "Socket not found"; auto-discovery is the fix).
4. Launches the fork. **Claude:** `cd <cwd> && <launcher> --resume <id> --fork-session`,
   picking the launcher that matches the session's config dir: `~/.claude-ant` →
   `claude::ant` (sources `.env.ant` auth + ensure step), `~/.claude` → `claude`, anything
   else → `CLAUDE_CONFIG_DIR=<cfg> claude`. Matching the wrapper matters — a bare
   `CLAUDE_CONFIG_DIR=… claude` skips `claude::ant`'s auth and lands "Not logged in".
   **pi:** `cd <cwd> && pi --fork <session.jsonl> --provider … --model … --thinking …`
   — see [pi specifics](#pi-specifics) for why those flags are mandatory.
5. Titles the new tab `fork: <name>` (`rpc tab.action`).
6. The `fork: <name>` title survives the fork's own tab-sync hook without any
   pre-seed: `sync_cmux_tab.py` (stateless, fires on `UserPromptSubmit` + `Stop`) treats a terminal tab
   whose title *contains* the session name as already in sync, and `fork: <name>`
   contains the inherited name by construction. pi ships no such hook, so its title is
   simply never contended.

## pi specifics

**Provider and model must be passed explicitly.** Unlike Claude Code (one account per
`CLAUDE_CONFIG_DIR`), pi keeps every subscription in a single `~/.pi/agent` and picks one
*per invocation* via `--provider`/`--model`. A bare `pi --fork <file>` would silently fall
back to the CLI default provider, so the script recovers the live pair from the **last
`model_change` entry** in the session JSONL and passes it through, plus the last
`thinking_level_change` as `--thinking`. `printf %q` quotes them — without it a model id
like `claude-opus-5[fast]` is a zsh glob.

**`PI_SESSION_FILE` / `PI_SESSION_ID` are documented but not always injected.** pi's
[environment-variables docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/environment-variables.md)
list them under "Bash Tool Session Environment", but pi 0.82.0 does not actually set them. The resolver therefore falls back to the
newest `*.jsonl` under the cwd's session dir, whose name pi mangles as
`"-" + cwd.replace("/", "-") + "--"` (e.g. `--Users-dh-projects-…-touchstone--`). This is
ambiguous only if two pi sessions share one cwd — ours wrote most recently, since the
resolver runs mid-turn. Set `PI_SESSION_FILE` explicitly to remove the guess.

**Titles are truncated to 40 chars.** pi auto-names a session from its first message, so
the raw name is a whole sentence.

**Fork lineage is recorded.** `pi --fork` writes `parentSession: <path>` into the new
session's first entry, so the fork point is traceable after the fact.

## Local vs remote — two transports, one extra hop

All cmux mutations use `cmux rpc <method>` (`surface.split` / `surface.create` /
`surface.send_text` / `tab.action`) — `rpc` over the high-level verbs because it
passes any server method straight through. The mode is decided by whether the cmux
app binary exists on this host (`/Applications/cmux.app/.../bin/cmux`):

- **Local** (on the cmux UI host): `run_cmux` hits the local app socket; the new
  surface is a shell on the same machine, so the fork command is sent straight to it.
- **Remote** (durable/mosh, e.g. `bonbon`): `run_cmux` ssh'es to the app host. But the
  split creates a fresh shell *on the mac*, while the session's cwd + the agent binary live
  on the remote — so a bare `cd` would fail (this was the "didn't ssh into bonbon" bug).
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

- Not inside cmux, no `cmux`/`jq`, or neither `PI_CODING_AGENT` nor
  `CLAUDE_CODE_SESSION_ID` → clear error, no action.
- Session never `/rename`d (no `.name`) → titles the tab `fork: <session-id>`
  (the tab-sync hook has no name to sync, so the title is safe).
- pi session is ephemeral (`--no-session`) or its log is malformed → named error, no action.
- **Forking *from* a fresh fork pane while the parent session is mid-turn can re-fork the
  parent.** The mtime fallback picks the most recently written log, and a busy parent
  out-writes a fork that has only just created its file. Confirmed live: right after a
  successful fork, `ls -t | head -1` still returned the *parent*. Harmless in the normal
  case (the resolver wants whichever session is actively writing, which is the caller's),
  but set `PI_SESSION_FILE` in the pane to remove the guess — or wait for pi to inject it
  as its docs already promise.
- Every capture pipeline ends `|| true`: under `set -e -o pipefail` a failed glob or `jq`
  inside `$(…)` aborts the script **silently**, swallowing the `die` that was meant to
  explain the problem. (Found by testing the missing-session path — it exited 1 with no
  output.)
- All cmux writes are best-effort; the fork still launches even if the rename
  fails.

## Related

- `~/.files/modules/claude/hooks/sync_cmux_tab.py` — the stateless `UserPromptSubmit` + `Stop` hook that
  keeps a tab's title in step with the session name (always `rpc tab.action` with
  `tab_id`; the `rename-tab` subcommand is broken on current cmux builds — it errors
  `not_found: Tab not found`). It skips any terminal tab whose title contains the
  session name — which is what protects this skill's `fork:` titles. On a remote box it
  resolves its own surface deterministically (cmux `top` pid → the mosh/zellij args
  carry the zellij session name) and renames over ssh — so a `/rename` on a durable
  session retitles the cmux panel too.
- `~/.files/modules/claude/hooks/lib/cmux-remote.sh` — the shared `run_cmux` /
  `cmux_is_local` transport both scripts source (local exec vs `ssh -n` to the app host;
  cmux socket auto-discovery).
