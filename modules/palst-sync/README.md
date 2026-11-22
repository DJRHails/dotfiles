# palst-sync

Keeps this host's Claude Code sessions (`~/.claude/projects`, `~/.claude-ant/projects`)
mirrored to palst. [`run.sh`](./run.sh) runs one `palst sync <store> --watch` per store,
the client flow palst's README documents. It runs as a launchd user agent on macOS and as a
systemd user service with linger on Linux.

**Installing starts a backfill.** `palst sync` always makes a full pass over the tree before
it starts watching, so the first start uploads every session already on disk. Each new
upload also gets an automatic first report. Decide on the backfill before you install.

Prerequisites, all checked by `run.sh` at start, which exits non-zero if any is missing:

- `palst` installed as a uv tool, **>= 0.74.2**. Older clients PUT a subagent transcript
  over its parent session's upload.
- `palst login` done (`palst whoami` succeeds).
- bash >= 5.1 (Homebrew bash on macOS).

Logs go to `~/.local/state/palst-sync/palst-sync.log` (macOS) or `journalctl --user -u
palst-sync` (Linux). Set `PALST_SYNC_CONCURRENCY` to change in-flight uploads (default 4).

Client-side secret redaction only knows what the service's environment can see: `~/.zshrc`
plus `$PALST_HOME/secrets.txt`, not your interactive shell's exports. The server-side scan
is the authoritative one.
