# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Schedule the daily fast-forward pull. Prefer a systemd user timer (with
# linger, so it runs on headless servers with no active login — bonbon/taffy);
# fall back to a user crontab entry where systemd --user is unavailable.
UPDATE="$DOTFILES/modules/dotfiles-autoupdate/update.sh"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"

chmod +x "$UPDATE"
mkdir -p "$LOG_DIR"

if platform::command_exists systemctl && systemctl --user show-environment >/dev/null 2>&1; then
  UNIT_DIR="$HOME/.config/systemd/user"
  mkdir -p "$UNIT_DIR"

  cat >"$UNIT_DIR/dotfiles-autoupdate.service" <<UNIT
[Unit]
Description=Daily dotfiles fast-forward pull
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $UPDATE
UNIT

  cat >"$UNIT_DIR/dotfiles-autoupdate.timer" <<UNIT
[Unit]
Description=Run dotfiles auto-update once a day

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
UNIT

  systemctl --user daemon-reload
  if systemctl --user enable --now dotfiles-autoupdate.timer; then
    # Let the user timer fire without an active session (headless servers).
    loginctl enable-linger "$USER" 2>/dev/null ||
      platform::sudo loginctl enable-linger "$USER" 2>/dev/null || true
    log::success "dotfiles-autoupdate: systemd user timer enabled (daily) + linger"
  else
    log::error "dotfiles-autoupdate: failed to enable systemd user timer"
  fi
else
  # cron fallback — idempotent (drop any prior line for this script first).
  MARKER="# dotfiles-autoupdate"
  TMP="$(mktemp)"
  crontab -l 2>/dev/null | grep -vF "$MARKER" >"$TMP" || true
  printf '17 9 * * * /usr/bin/env bash %s %s\n' "$UPDATE" "$MARKER" >>"$TMP"
  if crontab "$TMP"; then
    log::success "dotfiles-autoupdate: cron entry installed (daily 09:17)"
  else
    log::error "dotfiles-autoupdate: failed to install cron entry"
  fi
  rm -f "$TMP"
fi
