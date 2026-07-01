# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Schedule the daily fast-forward pull via a launchd user agent.
LABEL="info.hails.dotfiles-autoupdate"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UPDATE="$DOTFILES/modules/dotfiles-autoupdate/update.sh"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"

chmod +x "$UPDATE"
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$UPDATE</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>17</integer></dict>
  <key>StandardOutPath</key><string>$LOG_DIR/autoupdate.launchd.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/autoupdate.launchd.log</string>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
</dict>
</plist>
PLIST

# Reload cleanly: modern bootout/bootstrap, falling back to legacy load.
domain="gui/$(id -u)"
launchctl bootout "$domain/$LABEL" 2>/dev/null || true
if launchctl bootstrap "$domain" "$PLIST" 2>/dev/null; then
  log::success "dotfiles-autoupdate: launchd agent loaded (daily 09:17)"
else
  launchctl unload "$PLIST" 2>/dev/null || true
  if launchctl load "$PLIST" 2>/dev/null; then
    log::success "dotfiles-autoupdate: launchd agent loaded (legacy load)"
  else
    log::error "dotfiles-autoupdate: failed to load launchd agent $LABEL"
  fi
fi
