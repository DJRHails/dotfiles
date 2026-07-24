---
name: cmux-rebuild
description: "Manage the user's durable dev sessions — zellij sessions on remote hosts (bonbon, taffy) reached over mosh, plus the local host's (trifle) own detached zellij sessions, surfaced as cmux tabs via `ssh::durable` / `zellij::resume`. Load when the user wants to rebuild/resurrect lost cmux durable surfaces after a cmux restart or a mass disconnect, resume detached local zellij sessions, reconnect/sort sessions into per-repo cmux workspaces, retitle durable tabs, reap orphaned mosh-servers, or understand the `ssh::durable` picker and its green-● connected indicator. Triggers: 'ssh::durable', 'durable sessions', 'resurrect/rebuild cmux', 'lost my bonbon connections', 'reap mosh-servers', 'the green dot'."
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
  them — the user's live local sessions (e.g. a running Claude tab) are also `cmux-trifle-*`. Confirm
  via `cmux read-screen` (a connected one shows `Zellij (cmux-<host>-...)`) before closing any.
- **TMPDIR and zellij.** All local `zellij` invocations (list-sessions, dump-layout, delete-session,
  attach) must run with `TMPDIR=/tmp` or they silently see zero sessions / delete nothing. The
  script forces this; auto-attach.zsh's hop husk-delete was silently failing for exactly this
  reason until 2026-07-15 (husks accumulated → the zellij CLI wedge).
- **`cmux rpc` is gone.** Old tooling (`~/.config/cmux/snapshots/sort_bonbon.py`) used it and a
  `wrap-<session>` nesting convention; this script uses the current CLI (`workspace create`,
  `new-surface`, `send`, `rename-tab`, `read-screen`) instead.

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
