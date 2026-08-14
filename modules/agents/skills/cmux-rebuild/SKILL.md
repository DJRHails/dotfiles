---
name: cmux-rebuild
description: "Manage the user's durable dev sessions — zellij sessions on remote hosts (bonbon, taffy) reached over mosh, plus the local host's (trifle) own detached zellij sessions, surfaced as cmux tabs via `ssh::durable` / `zellij::resume`. Load when the user wants to rebuild/resurrect lost cmux durable surfaces after a cmux restart or a mass disconnect, resume detached local zellij sessions, reconnect/sort sessions into per-repo cmux workspaces, retitle durable tabs, reap orphaned mosh-servers, judge dead claude/pi sessions from their transcripts and resume the unfinished ones (claude::resume / pi::resume, local or via a remote zellij layout), or understand the `ssh::durable` picker and its green-● connected indicator. Triggers: 'ssh::durable', 'durable sessions', 'resurrect/rebuild cmux', 'cmux-resurrect', 'resume unfinished claude/pi sessions', 'lost my bonbon connections', 'reap mosh-servers', 'the green dot'."
---

# cmux durable sessions

The user's long-running dev work lives in **zellij sessions**, named `cmux-<host>-<id>` (e.g.
`cmux-bonbon-10-generous-pikes`). Remote hosts (`bonbon`, `taffy`) are reached over **mosh** (UDP
state-sync survives high-redraw TUIs; cmux's ws relay has per-keystroke latency that makes
zellij/tmux unusable) — each is surfaced as a **cmux tab** that runs `mosh <host> -- zellij attach
<session>`. The **local host** (`trifle`, the machine cmux runs on) has its own zellij sessions —
every cmux terminal surface auto-attaches one as a wrapper — which need no mosh: after a cmux
restart they sit detached with their work (claude, builds, vims) still running. Zellij sessions
persist across everything; only the cmux surfaces + mosh transports come and go.

Code: `modules/zellij/` — `mosh-zellij.zsh` (the `ssh::durable` picker + helpers + `zellij::resume`),
`durable-remote.sh` (remote menu/preview/reap generator, piped over ssh), `auto-attach.zsh`
(per-surface zellij attach + de-nest handoff).

## ssh::durable picker
`ssh::durable <host>` opens an fzf picker of the host's live sessions: each row is
`<cwd-fragment> · <3-5 word AI title>` (with the full cwd + short-id as a dim, searchable tail), a
green **●** marks sessions with a live local mosh client, and the preview shows id / one-line
summary / cwd / live screen. `enter` attaches, `ctrl-r` re-summarises, `ctrl-x` kills, `esc` →
fresh. Non-interactive: `--list`, `--attach <session>`, `--query <str>`, `--reap`.

**Connected detection (the green ●) is exact, not heuristic.** A session is "connected" iff a local
`mosh-client` process is talking to the UDP port its remote `mosh-server` is bound to. CPU-jiffie
sampling was tried and abandoned — keepalive work is sub-jiffie, so it's unreliable. The picker
computes this fresh each open from the local mosh-client ports.

## zellij::resume (local sessions)
`zellij::resume <session>` (mosh-zellij.zsh) is the local analogue of `ssh::durable --attach`:
reattach one of the local host's own zellij sessions in the current surface. It reuses the durable
de-nest handoff (`ssh::durable::go`), so from inside a surface's auto-attach wrapper it stages the
attach, detaches, and auto-attach.zsh deletes the wrapper husk and execs `zellij attach <session>`.
The staged attach forces `TMPDIR=/tmp` — zellij's socket dir follows TMPDIR, and a cmux surface
shell's default (`/var/folders/…` on macOS) can't see the sessions auto-attach creates under /tmp.

## Rebuild / resurrect (the common task)
After a **cmux restart** (it re-mints UUIDs and may not restore durable surfaces) or a **mass
disconnect** (e.g. all mosh-servers got reaped), the zellij sessions are still alive but their cmux
surfaces are gone. Rebuild them with `scripts/rebuild-durable.py` (hosts default to
`bonbon taffy <local>`):

```bash
python3 scripts/rebuild-durable.py [hosts...] --dry-run   # plan: sessions → per-repo workspace
python3 scripts/rebuild-durable.py [hosts...]             # create surfaces + send the attaches
python3 scripts/rebuild-durable.py [hosts...] --retry     # re-send to idle surfaces for stragglers
python3 scripts/rebuild-durable.py [hosts...] --retitle   # rename connected tabs to short session ids
python3 scripts/rebuild-durable.py [hosts...] --bind      # backfill cmux resume bindings (see below)
```

It sorts each live session into a cmux workspace named after its repo (cwd basename), grabs a
surface (the workspace's initial one first, then `new-surface`), and `cmux send`s the attach —
`ssh::durable <host> --attach <session>` for remote hosts, `zellij::resume <session>` for local
ones. Idempotent once connections settle — connected sessions are skipped (remote: exact
mosh-port check; local: a live `zellij attach` client process). Mid-settle, use `--retry` (which
reuses idle surfaces) rather than re-running the default pass — that would mint a duplicate
surface for every still-connecting session.

**Local sessions are filtered by work, not just liveness.** A local session is resumed only if it
is DETACHED (no attach client) and MEANINGFUL — its pane process tree runs something real (claude,
vim, a build), judged like `zellij::sweep-husks` (processes, not screen text: dump-screen is blank
for detached sessions and alternate-screen TUIs). Bare wrapper husks are never resumed; `--retry`'s
idle-surface detection and `--retitle` use the same meaningful-check so they never hijack or
mis-title a live local tab.

**Connecting many at once is racy** — sends into still-booting surfaces get dropped, and each
remote attach is an async de-nest + mosh handshake, so a single pass at ~30 sessions typically
lands ~60-95%. Expected workflow: run the default pass, then `--retry` a couple times (watch the
connected count climb), then `--retitle`. Stubborn stragglers: reconnect by hand with
`ssh::durable <host> --query <name>` / `zellij::resume <session>`.

### Gotchas
- **Nested vs de-nested.** Under load some surfaces don't de-nest — they keep a local-zellij wrapper
  (`cmux-trifle-*` title) with the mosh running *inside*. Functional, just a slightly messier Ctrl-O.
- **Stale titles.** `--retitle` reads the `[mosh] cmux-<host>-<id>` auto-title, falling back to the
  zellij status bar (`Zellij (cmux-<host>-<id>)`) via `cmux read-screen` — needed for nested
  surfaces AND locally-resumed ones, whose tab title goes stale at the deleted wrapper's name.
- **Idle leftover surfaces.** A racy pass can leave empty `cmux-trifle-*` surfaces. Don't blind-close
  them — the user's live local sessions (e.g. a running Claude tab) are also `cmux-trifle-*`. Use
  `scripts/clean-empty-surfaces.py` (below) rather than eyeballing `cmux read-screen`.
- **TMPDIR and zellij.** All local `zellij` invocations (list-sessions, dump-layout, delete-session,
  attach) must run with `TMPDIR=/tmp` or they silently see zero sessions / delete nothing. The
  script forces this; auto-attach.zsh's hop husk-delete was silently failing for exactly this
  reason until 2026-07-15 (husks accumulated → the zellij CLI wedge).
- **`cmux rpc` is gone.** Old tooling (`~/.config/cmux/snapshots/sort_bonbon.py`) used it and a
  `wrap-<session>` nesting convention; this script uses the current CLI (`workspace create`,
  `new-surface`, `send`, `rename-tab`, `read-screen`) instead.

## Cleaning empty surfaces after a rebuild
A rebuild leaves behind roughly as many junk surfaces as real ones (one pass here went 58 → 26).
`scripts/clean-empty-surfaces.py` finds and closes them:

```bash
python3 scripts/clean-empty-surfaces.py                      # report only (default)
python3 scripts/clean-empty-surfaces.py --close              # close everything classified empty
python3 scripts/clean-empty-surfaces.py --close --keep a,b   # …but spare these zellij sessions
```

Three kinds of junk, which look *opposite* on screen but are equally empty:

- **dead husk** — the pre-restart surface whose terminal exited; `cmux read-screen` is blank. Its
  resume binding still names the session it used to hold, and that session is normally live again
  on the NEW surface the rebuild made, so the husk is a pure duplicate.
- **bare wrapper** — a LIVE local auto-attach wrapper (`Zellij (cmux-<local>-…)`) sitting at a bare
  shell. The screen looks *busy* (zellij status bar, starship, direnv noise) but the pane tree runs
  nothing.
- **fresh agent** — a `pi`/`claude` that started but was never used. It defeats both other tests:
  the process tree sees a live agent (meaningful) and the screen is far from blank.

**Judge by process tree, never by screen text** — for the first two. Screen text calls a bare
wrapper "live" and a detached-but-working session "empty"; the pane process tree (reusing
`rebuild-durable.py`'s `local_meaningful()`, the `zellij::sweep-husks` rule) gets both right.

**The fresh-agent case needs the usage line, and only the usage line.** `0% │ ↑0 ↓0 │ $0` means no
tokens have ever been exchanged; a real session reads `31% │ ↑374 ↓134k`. Two tempting signals are
both WRONG: the startup banner still renders *above* a restored conversation, and a fresh session
*does* mint a session UUID — a rule keyed on "banner and no UUID" fires on the wrong sessions in
both directions. This check runs BEFORE the remote/local split, because a remote agent is invisible
to the local process-tree test and would otherwise get an unconditional keep. It doubles as the
context-% readout in the report.

Surfaces holding a remote mosh session, or a local session running real work, are otherwise kept.

### Gotchas
- **`--keep` the sessions you just resurrected.** A resurrected EXITED skeleton comes back as
  layout + cwd + scrollback with FRESH shells — no work running yet — so it is indistinguishable
  from a bare wrapper by the process-tree test. Without `--keep` the cleanup silently undoes the
  resurrection you just performed.
- **Close by UUID, not short ref.** Closing renumbers `surface:N` refs mid-loop; the script resolves
  every UUID up front from one `cmux tree --all --id-format both` snapshot.
- **Never close the caller.** The script always skips `$CMUX_SURFACE_ID` — closing it kills the
  agent session doing the cleaning.
- **A refused close looks like a successful one.** cmux reports close failures on **stderr with a
  non-zero exit while stdout stays EMPTY**, so a stdout-only helper prints `closed <surface>` for a
  close that errored. Use `cmux_checked()`, which folds in stderr and checks the return code.
- **cmux won't close a workspace's last surface** — `Error: invalid_state: Cannot close the last
  surface`. The script escalates automatically: on *that specific* message it closes the workspace
  instead, since a workspace whose only surface is empty holds nothing but its own name. It
  re-counts surfaces first (a concurrent rebuild pass can add one), and only that message
  escalates — any other error stays a reported failure rather than becoming a workspace deletion.
  Consequence: an empty workspace's NAME is not preserved. If a name is worth keeping, keep a real
  surface in it.

## Recovering what a dead skeleton was working on
Resurrecting an EXITED skeleton restores layout + cwd + a FRESH shell and **nothing else** — no
processes, and `pane_content` in the serialized metadata is only geometry, not scrollback. So a
resurrected skeleton reads as "dead" even though the attach succeeded. Do not chase skeletons when
what you actually want is the work.

What *is* serialized is each **pane title**, and `pi` sets it to `π - <task> - <repo>`. That turns
an anonymous pile of dead sessions into an index of lost work. zellij cannot `dump-layout` an
EXITED session, so read the file directly:

```bash
CACHE=~/Library/Caches/org.Zellij-Contributors.Zellij/contract_version_1/session_info
rg -o '^\s+title "(.*)"' "$CACHE/<session>/session-metadata.kdl"
```

Then map title → resumable session id in pi's own store
(`~/.pi/agent/sessions/<project-cwd-with-slashes-as-dashes>/<ts>_<uuid>.jsonl`) and resume with
`pi --session <uuid>`. Two traps: **pi RENAMES a session as the task evolves**, so scan every
`"name":` record rather than stopping at the first `session_info`; and most `[subagent] …` titles
are ephemeral pi workers, not sessions worth restoring (36 touchstone skeletons collapsed to 6 real
sessions). `resurrect` (`~/.local/bin/resurrect`) is claude-transcript-based and will not see pi
work at all.

## Resurrecting unfinished agent work (judge-and-resume)
When sessions die — a local reboot kills every trifle zellij server, a remote skeleton EXITs, a tab
gets killed — most of the claude/pi conversations inside them ended **at rest** on a completed
answer. Resurrect only the ones that died mid-task. The workflow (proven over a 2026-08-14 sweep:
41 transcripts judged across trifle + taffy, 6 resumed):

1. **Inventory the dead.** Local: EXITED `zellij list-sessions` + the serialized pane titles
   (previous section) name the work — `✳ <task>` is claude, `π - <task> - <repo>` is pi. When
   titles are generic or metadata is missing (common on remote hosts), go by transcripts: recent
   files under `~/.claude*/projects/` and `~/.pi/agent/sessions/`, excluding `*/subagents/*`.
2. **Establish liveness before judging — a live session's transcript looks identical to a dead
   one's.** Never resume a session that may be attached to a live tab; that runs it twice.
   fd-scanning is USELESS (claude and pi append-and-close; no held file handle). What works:
   - **Statusline ids**: both TUIs print their session uuid in the footer — `cmux read-screen`
     each live tab and regex the uuid out. Any transcript matching a live tab's id is live.
   - **pi process etimes bound the candidates**: a pi session file *created* after every live
     `pi` process started cannot belong to any of them — dead for certain.
3. **Judge from the last turns**: last real user ask vs last assistant turn. FINISHED = the final
   assistant text is a completion report with nothing outstanding. UNFINISHED = pending tool call,
   an unanswered ask or AskUserQuestion, or self-flagged undone items ("Not committed"). Fan the
   reading out to subagents (a few files each, head/tail/jq only — never whole transcripts). Traps:
   - **mtime is not activity.** Syncs and bookkeeping records (`last-prompt`, `ai-title`) bump
     mtimes long after the conversation ended; a batch of files sharing one mtime to the second is
     a sync artifact. Judge by record timestamps inside the file.
   - `[subagent]`-named pi sessions and single-prompt headless one-shots are ephemeral workers —
     their output was already consumed by a parent; never resume them.
   - `/tmp`-cwd claude project dirs are batch workers; `/clear`-only 5-line files are empty stubs.
4. **Resume each unfinished session** with `scripts/resume-agent-session.py`:

```bash
python3 scripts/resume-agent-session.py --kind pi --id 019ffb15-8130 \
    --slug wall-fixes --workspace sharetrawl --host taffy        # remote
python3 scripts/resume-agent-session.py --kind claude --id 375fda41 \
    --slug submodule-token --workspace hails.info                # local
```

It resolves the id fragment against the host's transcript stores (aborting if ambiguous — pi's
`--session` takes partial uuids and `head -1` would silently pick one of two), then: **local**,
sends `claude::resume <id>` / `pi::resume <id>` (modules/claude + modules/pi aliases; they cd to
the transcript's recorded cwd and route the owning config dir) into a fresh surface; **remote**,
declares the resume in a layout (`zsh -ic "<kind>::resume <id> || exec zsh"` — write-chars is
dropped against detached sessions, and the `|| exec zsh` keeps a failed resume debuggable) and
sends `mosh <host> -- zellij --session cmux-<host>-<kind>-<slug> --new-session-with-layout <abs
path>`. Sends into a booting surface are eaten silently (~half of first sends), so it polls for
the session id on the statusline / the session existing remotely and re-sends until one lands,
then retitles the tab `<slug> <short-id>`. Layout-created sessions carry no resume binding
(`--bind` skips them); the next rebuild pass reconnects them via REMOTE_CONN's `zellij --session`
match.

## Moving a pi session to another host
pi keys a session to a project by the DIRECTORY it lives in, so migrating means placing the file in
the target's project dir and rewriting the `cwd` in its first `{"type":"session"}` line. Leave
historical paths inside tool output alone — they are a record, not live state. The copies then
diverge: new work on the target does not appear on the source.

- **Check the format loads on the target FIRST.** Hosts drift (trifle 0.82.0 vs taffy 0.80.6 for
  `version 3` sessions). `pi --export <session-file>` loads and exits — a compatibility test that
  needs no TTY. Note `--export` takes the session file as INPUT, not an output path.
- **`zellij action write-chars` is silently dropped** against a session with no attached client, so
  you cannot pre-create a detached session and type a command into it — it reports success and does
  nothing. Declare the command in a **layout** instead, so the agent is the session's own process:
  `layout { pane command="pi" cwd="<repo>" { args "--session" "<uuid>" } }`, started with
  `zellij --session <name> --new-session-with-layout <path>`.
- **Use the remote's ABSOLUTE paths in anything sent through mosh.** `$HOME` in a `cmux send` is
  expanded by the LOCAL shell before mosh runs, so the remote receives `/Users/dh/…` and zellij
  exits instantly.
- **Sessions created that way are invisible to connected-detection** unless it matches
  `zellij --session` as well as `zellij attach` (fixed in `REMOTE_CONN`). Otherwise the next rebuild
  pass judges them disconnected and mints duplicate surfaces.

## Restart survival — resume bindings
What "a restart" does to sessions:

- **cmux app restart/quit:** zellij servers survive the pty SIGHUP → sessions sit **detached**
  with work running. Reattach via the rebuild above, or automatically via resume bindings (next
  paragraph).
- **macOS reboot:** servers die — no detach can save processes. zellij session-serialization
  (`session_serialization true` + viewport in config.kdl) leaves EXITED skeletons; `zellij attach`
  resurrects the layout/cwds/scrollback with fresh shells. Claude work comes back via `resurrect`
  (`claude --resume`), not the skeleton.

**Resume bindings** make reattach hands-free: every attach path registers a per-surface restart
command with cmux (`cmux surface resume set`) — auto-attach.zsh (local wrapper sessions, guarded
to `$CMUX_REMOTE_TRANSPORT` empty), `zellij::resume` (kind `zellij`, command
`env TMPDIR=/tmp zellij attach <session>`), and `ssh::durable::attach` (kind `zellij-mosh`,
command `mosh <host> -- zellij attach <session>`). On reopen, cmux restores each terminal surface
by running its binding — reattaching the detached session (app restart) or resurrecting the
serialized skeleton (reboot). `--bind` backfills bindings onto already-connected tabs (needed once
for tabs attached before this existed). Bindings are gated by **signed prefix approvals**: the
user must set the `env TMPDIR=/tmp zellij attach`, `mosh bonbon -- zellij attach`, and
`mosh taffy -- zellij attach` prefixes to Auto-Restore in **Settings → Terminal → Resume
Commands** (CLI-set bindings default to `approval_policy: manual`; approval is UI-only by design).
Fresh remote sessions made via the picker's Esc-fallback have no binding until their first
`--attach`/rebuild. Registration can silently miss during a surface's first seconds (the surface
API races its boot — observed once) — auto-attach logs each attempt as `resume-bind
set|unchanged|set-FAILED|skip` in `~/.cache/cmux-zellij/attempts.log`, and `--bind` backfills
misses.

## Reaping orphaned mosh-servers
mosh-servers linger after a client disconnects (lots of cruft over time). `ssh::durable <host> --reap`
kills mosh-servers with no live local client that are >120s old. **Opt-in only** — it is NOT
auto-fired on picker teardown (that was removed: a teardown reap whose live-client detection raced
could kill still-attached mosh-servers and drop every tab, which is exactly the "lost them all
again" failure). The green ● is computed fresh on each picker open (`compute_connf`), so it never
depended on the reap. **Safe** — reap only drops the stale transport; the zellij session persists
and the picker re-moshes. Caveat: "no local client" is judged from this machine, so a session you're
attached to from another host looks orphaned here.

## cmux CLI quick ref (current)
`cmux workspace list` · `cmux list-pane-surfaces --workspace <ws>` · `cmux workspace create --name <n>
--cwd <d> --focus false` (spawns an initial surface) · `cmux new-surface --workspace <ws> --focus
false` (prints the new ref) · `cmux send --surface <s> "cmd\n"` (inject a command) · `cmux
rename-tab --surface <s> <title>` · `cmux read-screen --surface <s> --workspace <ws>` · `cmux
close-workspace --workspace <ws>` · `cmux surface resume set|get|show|clear --surface <s>
--workspace <ws>` (restart command metadata; `set --kind <k> --name <n> --shell <cmd>`).
