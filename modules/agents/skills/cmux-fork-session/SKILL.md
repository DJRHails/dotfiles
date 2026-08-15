---
name: cmux-fork-session
description: "Fork the current agent session — Claude Code or pi — into a new cmux split pane (or tab): opens a split beside the caller, relaunches this session forked (claude --fork-session / pi --fork), titles it 'fork: <name>', and keeps that title. Use when the user asks to fork/duplicate/branch the current session into a new split or tab. Works whether the session is local on the cmux UI host or running on a durable/mosh remote (e.g. bonbon). Requires the macOS cmux app on the UI host — skip if the session was not started from cmux."
---

# cmux: fork this session into a new split (or tab)

Forks the **current** agent session into a **new cmux split pane** (or tab) so you can branch the
conversation and keep working in both, side by side. The new surface gets a *new* session id with
the same history up to the fork point, is titled `fork: <session-name>`, and keeps that title.

Both agents are supported; the flavour is autodetected (override with `FORK_AGENT`):

| agent | detected by | fork command |
| --- | --- | --- |
| Claude Code | `CLAUDE_CODE_SESSION_ID` | `claude --resume <id> --fork-session` |
| pi | `PI_CODING_AGENT=true` | `pi --fork <session.jsonl> --provider … --model … --thinking …` |

pi is checked first: when nested (a pi session launched from Claude Code) pi is the innermost, and
is the session the caller is actually talking to.

## Usage

Run the reference script — it reads everything from the environment:

```bash
bash .../cmux-fork-session/reference/fork-session.sh                 # split right, title "fork: <name>"
bash .../cmux-fork-session/reference/fork-session.sh "branch: " down # split downward, custom prefix
bash .../cmux-fork-session/reference/fork-session.sh "fork: " tab    # new tab instead of a split
```

Second arg `where`: `right` (default) | `left` | `up` | `down` for a split, or `tab` for a sibling
tab. (The skill base directory is printed when the skill loads.)

Env overrides: `FORK_AGENT=claude|pi` forces the flavour; `PI_SESSION_FILE` / `PI_SESSION_DIR`
pin pi's session log; `CMUX_DURABLE_HOST` / `CMUX_APP_HOST` override the remote and app hosts;
`CMUX_APP_BIN` pins the cmux binary.

## What it does

1. **Resolve the session** from env, never the process tree: `CLAUDE_CODE_SESSION_ID` +
   `CLAUDE_CONFIG_DIR`, or pi's `PI_SESSION_FILE` / `PI_SESSION_ID`. Read the session **name** and
   project **cwd** from `$CLAUDE_CONFIG_DIR/sessions/<pid>.json` (Claude), or the session JSONL's
   first `session` entry plus last `session_info` entry (pi).
2. **Resolve this session's live cmux surface.** Locally, trust the freshly-injected
   `CMUX_SURFACE_ID`. On a remote, find the surface whose **title contains** a match key — see
   [Surface resolution](#surface-resolution). The resolved id also heals the live-ids sidecar so
   `cmux-session-tab` recovers too.
3. **Create the surface**: `cmux rpc surface.split` beside the caller, or `surface.create` for a
   tab.
4. **Launch the fork.** *Claude:* `cd <cwd> && <launcher> --resume <id> --fork-session`, choosing
   the launcher that matches the session's config dir — `~/.claude-ant` → `claude::ant` (sources
   `.env.ant` auth + ensure step), `~/.claude` → `claude`, otherwise
   `CLAUDE_CONFIG_DIR=<cfg> claude`. Matching the wrapper matters: a bare `CLAUDE_CONFIG_DIR=…
   claude` skips `claude::ant`'s auth and lands "Not logged in". *pi:* `cd <cwd> && pi --fork
   <session.jsonl> --provider … --model … --thinking …` (see [pi specifics](#pi-specifics)).
5. **Title the new tab** `fork: <name>` via `rpc tab.action`.

The `fork: <name>` title survives the fork's own tab-sync hook with no pre-seed: `sync_cmux_tab.py`
(stateless, fires on `UserPromptSubmit` + `Stop`) treats a terminal tab whose title *contains* the
session name as already in sync, and `fork: <name>` contains the inherited name by construction. pi
ships no such hook, so its title is never contended.

## Surface resolution

Handled by `cmux_surface_for_zellij` in the transport lib; nothing to do by hand. Locally the
freshly-injected `CMUX_SURFACE_ID` is trusted. Remotely, two strategies in order:

1. **Pid chain** (deterministic) — `cmux top` maps surfaces to the pids running in them, and `ps`
   on the app host says which pid is the mosh/zellij client for this session. No titles involved.
2. **Title match** (fallback) — the Claude session name, then `$ZELLIJ_SESSION_NAME`. A heuristic,
   because a pane's title can go stale against the session actually running in it.

Neither the forwarded `CMUX_SURFACE_ID`/live-ids sidecar (go stale on a remote → "Workspace not
found") nor "focused" (drifts between tabs) is used remotely.

If both strategies fail the script prints the pid-chain and title diagnoses, every open surface
title, and the exact `tab.action` command to retitle this tab — so the fix is visible rather than
something you have to know.

## Local vs remote — two transports, one extra hop

All cmux mutations go through `cmux rpc <method>` (`surface.split` / `surface.create` /
`surface.send_text` / `tab.action`) rather than the high-level verbs, because `rpc` passes any
server method straight through. Each call goes via `run_cmux`, the shared transport in
[`cmux-remote.sh`](../../../claude/hooks/lib/cmux-remote.sh) that the tab-sync hook also uses, so
the two cannot drift. Mode is decided by whether a cmux binary exists on this host.

- **Local** (the cmux UI host): `run_cmux` execs the local binary; the new surface is a shell on
  the same machine, so the fork command is sent straight to it.
- **Remote** (durable/mosh, e.g. `bonbon`): `run_cmux` ssh'es (`ssh -n`) to the app host, args
  base64-encoded per-arg so the JSON survives ssh re-quoting. The split creates a fresh shell *on
  the mac*, while the session's cwd and agent binary live on the remote — so a bare `cd` cannot
  work. Instead the script (running on the remote) writes a one-pane zellij **layout** that
  launches the fork, then drives the mac surface to `mosh <remote> -- zellij
  --new-session-with-layout <layout> --session <forksess>`. The `--session`/`--layout` pair
  *attaches* and errors if absent; `--new-session-with-layout` is what *creates*. The split's login
  shell needs a beat to reach a prompt and drops input typed too early, so the send is **retried
  until the session actually comes up** — a local `zellij list-sessions` on the fork's own host is
  the authoritative readiness check, re-checked before each resend so the hop is never typed into
  an already-attached mosh pane. The fork lands in its own **durable zellij session**, with a
  live-id sidecar written so `cmux-session-tab` can drive it afterwards.

The `zsh -lc` outer hop (login, non-interactive) gets PATH but does **not** source `.zshrc`, so
`auto-attach.zsh` doesn't fire and fight the explicit attach. The layout pane's `zsh -ic` is
interactive so `claude::ant` resolves, and auto-attach there no-ops because `$ZELLIJ` is already
set.

### Transport helpers

Everything that moves between cmux builds is encoded in `cmux-remote.sh`, so callers use the
wrapper and cannot get it wrong:

| helper | handles |
| --- | --- |
| `run_cmux` / `cmux_is_local` | binary probing across app layouts, on both ends of the ssh hop |
| `cmux_tree` | `--id-format` must follow the subcommand, else cmux exits 0 with empty output |
| `cmux_rename_tab <surface-uuid>` | `tab.action` takes `tab_id` = a **surface** uuid, not a workspace one |
| `cmux_surface_for_zellij` | the deterministic pid chain above |

`$CMUX_APP_BIN` overrides the probe. `CMUX_SOCKET_PATH` is deliberately never forced — cmux
auto-discovers its socket, and the location differs between builds.

`surface.*` methods target with `surface_id`; passing `surface`/`tab` to `tab.action` is silently
ignored and acts on the focused surface.

## pi specifics

**Provider and model must be passed explicitly.** Unlike Claude Code (one account per
`CLAUDE_CONFIG_DIR`), pi keeps every subscription in a single `~/.pi/agent` and picks one *per
invocation* via `--provider`/`--model`. A bare `pi --fork <file>` silently falls back to the CLI
default provider, so the script recovers the live pair from the **last `model_change` entry** in
the session JSONL and passes it through, plus the last `thinking_level_change` as `--thinking`.
`printf %q` quotes them — without it a model id like `claude-opus-5[fast]` is a zsh glob.

**`PI_SESSION_FILE` / `PI_SESSION_ID` are documented but not always injected.** pi's
[environment-variables docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/environment-variables.md)
list them under "Bash Tool Session Environment", but pi 0.82.0 does not set them. The resolver
falls back to the newest `*.jsonl` under the cwd's session dir, whose name pi mangles as
`"-" + cwd.replace("/", "-") + "--"` (e.g. `--Users-dh-projects-…-touchstone--`). Ambiguous only if
two pi sessions share one cwd. Set `PI_SESSION_FILE` explicitly to remove the guess.

**Titles are truncated to 40 chars.** pi auto-names a session from its first message, so the raw
name is a whole sentence.

**Fork lineage is recorded.** `pi --fork` writes `parentSession: <path>` into the new session's
first entry, so the fork point is traceable after the fact.

## Robustness / edge cases

- Not inside cmux, no `cmux`/`jq`, or neither `PI_CODING_AGENT` nor `CLAUDE_CODE_SESSION_ID` →
  clear error, no action.
- Session never `/rename`d (no `.name`) → titles the tab `fork: <session-id>`; the tab-sync hook
  has no name to sync, so the title is safe.
- pi session is ephemeral (`--no-session`) or its log is malformed → named error, no action.
- **Forking *from* a fresh fork pane while the parent session is mid-turn can re-fork the parent.**
  The mtime fallback picks the most recently written log, and a busy parent out-writes a fork that
  has only just created its file. Harmless in the normal case (the resolver wants whichever session
  is actively writing, which is the caller's), but set `PI_SESSION_FILE` in the pane to remove the
  guess.
- Every capture pipeline ends `|| true`: under `set -e -o pipefail` a failed glob or `jq` inside
  `$(…)` aborts the script **silently**, swallowing the `die` that was meant to explain the
  problem.
- All cmux writes are best-effort; the fork still launches even if the rename fails.

## Related

- `~/.files/modules/claude/hooks/sync_cmux_tab.py` — the stateless `UserPromptSubmit` + `Stop` hook
  that keeps a tab's title in step with the session name (always `rpc tab.action` with `tab_id`;
  the `rename-tab` subcommand errors `not_found: Tab not found` on current builds). It skips any
  terminal tab whose title contains the session name, which is what protects this skill's `fork:`
  titles. On a remote box it resolves its own surface deterministically (cmux `top` pid → the
  mosh/zellij args carry the zellij session name) and renames over ssh, so a `/rename` on a durable
  session retitles the cmux panel too.
- `~/.files/modules/claude/hooks/lib/cmux-remote.sh` — the shared `run_cmux` / `cmux_is_local`
  transport both scripts source (local exec vs `ssh -n` to the app host, binary probing, socket
  auto-discovery).
