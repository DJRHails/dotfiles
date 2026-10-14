# dotfiles-autoupdate

Keeps this machine's `~/.files` checkout current with a **once-daily
fast-forward pull**. Runs on macOS (launchd user agent) and Linux (systemd user
timer, or cron fallback).

**Safe by construction** — [`update.sh`](./update.sh):

- carries local changes over the pull on a stash, and keeps the stash instead of
  popping it when it would conflict (never clobbers WIP),
- **fast-forward only** — a diverged branch is left for a human, never auto-merged,
- **never pushes** — pull-only, one direction.

**Submodules follow their pins** — [`sync-submodules.sh`](./sync-submodules.sh), run after a
fast-forward and on an already-up-to-date tree. Vendored skills load live from the checkout, so
a bumped pin must reach the submodule's worktree. Each initialised submodule that lags the
commit recorded at `HEAD` is checked out (detached) at that commit, fetching it first if it
is missing — but only when that is safe:

- its HEAD is **detached** — a checked-out branch is somebody's work, so it is skipped
  (`skip — on branch <name>`),
- it has **no modified or staged tracked files** — otherwise skipped
  (`skip — modified tracked files`),
- its HEAD is reachable from a branch, remote-tracking ref or tag, or is a commit the
  superproject itself pinned — otherwise it holds commits made on the detached HEAD,
  which the move would orphan, so it is skipped
  (`skip — HEAD is on no branch, remote or tag`),
- untracked files (e.g. a `.data/` of worktrees) never block the move and are kept,
- a failed fetch skips that submodule only (`skip — pin <sha> not available`).

Uninitialised submodules are left to `bootstrap.sh`. Nothing is forced or reset.

Logs to `$XDG_STATE_HOME/dotfiles/autoupdate.log` (default
`~/.local/state/dotfiles/autoupdate.log`).

## Pull now

`dotfiles::update` ([`aliases.zsh`](./aliases.zsh)) is the manual counterpart —
same fast-forward-only pull and the same submodule step, but run on demand and
with the output on the terminal instead of in the log.

## Install

Picked up by `bootstrap.sh` (in the `--cli` server set, so bonbon/taffy get it
too). Or directly:

```sh
./bootstrap.sh dotfiles-autoupdate
```

- **macOS** → `~/Library/LaunchAgents/info.hails.dotfiles-autoupdate.plist`, daily 09:17.
- **Linux** → `~/.config/systemd/user/dotfiles-autoupdate.{service,timer}` (`OnCalendar=daily`,
  `Persistent=true`) + `loginctl enable-linger` so it fires on headless servers.

## Check / disable

```sh
# macOS
launchctl print "gui/$(id -u)/info.hails.dotfiles-autoupdate"
launchctl bootout "gui/$(id -u)/info.hails.dotfiles-autoupdate"   # disable

# Linux
systemctl --user list-timers dotfiles-autoupdate.timer
systemctl --user disable --now dotfiles-autoupdate.timer          # disable

tail -f ~/.local/state/dotfiles/autoupdate.log                    # what it did
```
