# dotfiles-autoupdate

Keeps this machine's `~/.files` checkout current with a **once-daily
fast-forward pull**. Runs on macOS (launchd user agent) and Linux (systemd user
timer, or cron fallback).

**Safe by construction** — [`update.sh`](./update.sh):

- skips if the working tree has local changes (never clobbers WIP),
- **fast-forward only** — a diverged branch is left for a human, never auto-merged,
- **never pushes** — pull-only, one direction.

Logs to `$XDG_STATE_HOME/dotfiles/autoupdate.log` (default
`~/.local/state/dotfiles/autoupdate.log`).

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
