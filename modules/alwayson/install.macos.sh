. "$DOTFILES/scripts/core/main.sh"

BACKUP_DIR="$DOTFILES/modules/alwayson/.backup"

# -- Backup existing settings ----------------------------------------------
if [ ! -f "$BACKUP_DIR/pmset.txt" ]; then
  mkdir -p "$BACKUP_DIR"
  pmset -g custom > "$BACKUP_DIR/pmset.txt"
  launchctl print system/com.openssh.sshd > "$BACKUP_DIR/sshd-launchctl.txt" 2>/dev/null || true
  nvram AutoBoot > "$BACKUP_DIR/nvram.txt" 2>/dev/null || true
  sysctl kern.watchdog > "$BACKUP_DIR/sysctl.txt" 2>/dev/null || true
  if [ -f /etc/ssh/sshd_config ]; then
    cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config"
  fi
  log::result $? "Backed up existing settings to $BACKUP_DIR"
else
  log::success "Backup already exists at $BACKUP_DIR"
fi

# Read current power settings once (avoids repeated sudo)
CURRENT_PMSET="$(pmset -g)"

# -- Prevent Sleep --------------------------------------------------------
if echo "$CURRENT_PMSET" | grep -q "^ sleep.*0"; then
  log::success "Sleep already disabled"
else
  platform::sudo pmset -a sleep 0
  platform::sudo pmset -a disksleep 0
  platform::sudo pmset -a displaysleep 0
  platform::sudo pmset -a powernap 0
  platform::sudo pmset -a standby 0
  platform::sudo pmset -a autopoweroff 0
  platform::sudo pmset -a hibernatemode 0
  log::result $? "Sleep disabled"
fi

# -- Network Always On ----------------------------------------------------
if echo "$CURRENT_PMSET" | grep -q "^ womp.*1"; then
  log::success "Network already always on"
else
  platform::sudo pmset -a womp 1
  platform::sudo pmset -a tcpkeepalive 1
  platform::sudo pmset -a networkoversleep 0
  log::result $? "Network always on"
fi

# -- Auto Recovery ---------------------------------------------------------
if echo "$CURRENT_PMSET" | grep -q "^ autorestart.*1"; then
  log::success "Auto recovery already configured"
else
  platform::sudo pmset -a autorestart 1
  platform::sudo pmset -a panicrestart 30
  platform::sudo pmset repeat wakeorpoweron MTWRFSU 00:00:00 2>/dev/null || true
  platform::sudo sysctl -w kern.watchdog=1 2>/dev/null || true
  log::result $? "Auto recovery"
fi

# -- Boot & Login ----------------------------------------------------------
if launchctl print system/com.openssh.sshd &>/dev/null; then
  log::success "Remote login already enabled"
else
  platform::sudo launchctl enable system/com.openssh.sshd
  platform::sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
  log::result $? "Remote login enabled"
fi
if nvram AutoBoot 2>/dev/null | grep -q "%03"; then
  log::success "AutoBoot already configured"
else
  platform::sudo nvram AutoBoot=%03 2>/dev/null || true
  log::result $? "AutoBoot configured"
fi

# -- SSH Keep-Alive --------------------------------------------------------
SSHD_CONFIG="/etc/ssh/sshd_config"
if ! grep -q "ClientAliveInterval 60" "$SSHD_CONFIG" 2>/dev/null; then
  platform::sudo tee -a "$SSHD_CONFIG" > /dev/null <<'SSHEOF'

# Added by dotfiles/always-on
ClientAliveInterval 60
ClientAliveCountMax 3
TCPKeepAlive yes
SSHEOF
  log::result $? "SSH keep-alive configured"
else
  log::success "SSH keep-alive already configured"
fi

# -- Caffeinate Daemon -----------------------------------------------------
PLIST="/Library/LaunchDaemons/com.local.caffeinate.plist"
if [ ! -f "$PLIST" ]; then
  platform::sudo tee "$PLIST" > /dev/null <<'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.caffeinate</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-s</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLISTEOF
  platform::sudo launchctl load "$PLIST"
  log::result $? "Caffeinate daemon"
else
  log::success "Caffeinate daemon already installed"
fi
