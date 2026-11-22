# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Keep this Mac's Claude Code sessions mirrored to palst via a launchd user agent.
LABEL="info.hails.palst-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
RUN="$DOTFILES/modules/palst-sync/run.sh"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/palst-sync"

chmod +x "$RUN"
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>bash</string>
    <string>$RUN</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>60</integer>
  <key>StandardOutPath</key><string>$LOG_DIR/palst-sync.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/palst-sync.log</string>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
PLIST

domain="gui/$(id -u)"
launchctl bootout "$domain/$LABEL" 2>/dev/null || true
if launchctl bootstrap "$domain" "$PLIST"; then
  log::success "palst-sync: launchd agent loaded (log: $LOG_DIR/palst-sync.log)"
else
  log::error "palst-sync: failed to load launchd agent $LABEL"
fi
