# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Keep this host's Claude Code sessions mirrored to palst via a systemd user service, with
# linger so it runs on headless servers with no active login.
RUN="$DOTFILES/modules/palst-sync/run.sh"
UNIT_DIR="$HOME/.config/systemd/user"

if ! platform::command_exists systemctl || ! systemctl --user show-environment >/dev/null 2>&1; then
  log::error "palst-sync: needs systemd --user; not installed on this host"
  exit 0
fi

chmod +x "$RUN"
mkdir -p "$UNIT_DIR"

cat >"$UNIT_DIR/palst-sync.service" <<UNIT
[Unit]
Description=palst sync --watch: this host's Claude Code sessions -> palst
After=network-online.target
StartLimitIntervalSec=3600
StartLimitBurst=30

[Service]
Type=simple
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/env bash $RUN
Restart=on-failure
RestartSec=60
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
if systemctl --user enable --now palst-sync.service; then
  loginctl enable-linger "$USER" 2>/dev/null ||
    platform::sudo loginctl enable-linger "$USER" 2>/dev/null || true
  log::success "palst-sync: systemd user service enabled + linger"
else
  log::error "palst-sync: failed to enable systemd user service"
fi
