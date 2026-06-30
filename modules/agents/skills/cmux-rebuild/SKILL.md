---
name: cmux-rebuild
description: "Manage the user's durable remote dev sessions — mosh+zellij sessions on a remote host (default bonbon), surfaced as cmux tabs via `ssh::durable`. Load when the user wants to rebuild/resurrect lost cmux durable surfaces after a cmux restart or a mass disconnect, reconnect/sort remote sessions into per-repo cmux workspaces, retitle durable tabs, reap orphaned mosh-servers, or understand the `ssh::durable` picker and its green-● connected indicator. Triggers: 'ssh::durable', 'durable sessions', 'resurrect/rebuild cmux', 'lost my bonbon connections', 'reap mosh-servers', 'the green dot'."
---

# cmux durable sessions

The user's long-running dev work lives in **zellij sessions on a remote host** (default `bonbon`),
named `cmux-<host>-<id>` (e.g. `cmux-bonbon-10-generous-pikes`). They're reached over **mosh** (UDP
state-sync survives high-redraw TUIs; cmux's ws relay has per-keystroke latency that makes
zellij/tmux unusable). Each is surfaced as a **cmux tab** that runs `mosh <host> -- zellij attach
<session>`. The zellij sessions persist on the remote across everything; only the local cmux
surfaces + mosh transports come and go.

Code: `modules/zellij/` — `mosh-zellij.zsh` (the `ssh::durable` picker + helpers), `durable-remote.sh`
(remote menu/preview/reap generator, piped over ssh), `auto-attach.zsh` (per-surface zellij attach
+ de-nest handoff).

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

## Rebuild / resurrect (the common task)
After a **cmux restart** (it re-mints UUIDs and may not restore durable surfaces) or a **mass
disconnect** (e.g. all mosh-servers got reaped), the remote zellij sessions are still alive but
their cmux surfaces are gone. Rebuild them with `scripts/rebuild-durable.py`:

```bash
python3 scripts/rebuild-durable.py [host] --dry-run   # plan: sessions → per-repo workspace
python3 scripts/rebuild-durable.py [host]             # create surfaces + send the attaches
python3 scripts/rebuild-durable.py [host] --retry     # re-send to idle surfaces for stragglers
python3 scripts/rebuild-durable.py [host] --retitle   # rename connected tabs to short session ids
```

It sorts each live remote session into a cmux workspace named after its repo (cwd basename), creates
a surface, and `cmux send`s `ssh::durable <host> --attach <session>` (the current de-nesting attach).
Idempotent — already-connected sessions are skipped (port check), so re-running is safe.

**Connecting many at once is racy** — each attach is an async de-nest + mosh handshake, so a single
pass at ~30 sessions typically lands ~60-95%. Expected workflow: run the default pass, then
`--retry` a couple times (watch the connected count climb), then `--retitle`. Stubborn stragglers:
reconnect by hand with `ssh::durable <host> --query <name>`.

### Gotchas
- **Nested vs de-nested.** Under load some surfaces don't de-nest — they keep a local-zellij wrapper
  (`cmux-trifle-*` title) with the mosh running *inside*. Functional, just a slightly messier Ctrl-O.
  `--retitle` handles both: it reads the `[mosh] cmux-<host>-<id>` title, falling back to the remote
  zellij status bar (`Zellij (cmux-<host>-<id>)`) via `cmux read-screen` for nested ones.
- **Idle leftover surfaces.** A racy pass can leave empty `cmux-trifle-*` surfaces. Don't blind-close
  them — the user's live local sessions (e.g. a running Claude tab) are also `cmux-trifle-*`. Confirm
  via `cmux read-screen` (a connected one shows `Zellij (cmux-<host>-...)`) before closing any.
- **`cmux rpc` is gone.** Old tooling (`~/.config/cmux/snapshots/sort_bonbon.py`) used it and a
  `wrap-<session>` nesting convention; this script uses the current CLI (`workspace create`,
  `new-surface`, `send`, `rename-tab`, `read-screen`) instead.

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
`cmux list-workspaces` · `cmux list-pane-surfaces --workspace <ws>` · `cmux workspace create --name <n>
--cwd <d> --focus false` · `cmux new-surface --workspace <ws> --focus false` (prints the new ref) ·
`cmux send --surface <s> "cmd\n"` (inject a command) · `cmux rename-tab --surface <s> <title>` ·
`cmux read-screen --surface <s> --workspace <ws>`.
