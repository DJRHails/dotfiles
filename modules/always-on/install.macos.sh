. "$DOTFILES/scripts/core/main.sh"

# -- Prevent Sleep --------------------------------------------------------
platform::sudo pmset -a sleep 0
platform::sudo pmset -a disksleep 0
platform::sudo pmset -a displaysleep 0
platform::sudo pmset -a powernap 0
platform::sudo pmset -a standby 0
platform::sudo pmset -a autopoweroff 0
platform::sudo pmset -a hibernatemode 0
log::result $? "Sleep disabled"

# -- Network Always On ----------------------------------------------------
platform::sudo pmset -a womp 1
platform::sudo pmset -a tcpkeepalive 1
platform::sudo pmset -a networkoversleep 0
log::result $? "Network always on"

# -- Auto Recovery ---------------------------------------------------------
platform::sudo pmset -a autorestart 1
platform::sudo pmset -a panicrestart 30
platform::sudo pmset repeat wakeorpoweron MTWRFSU 00:00:00
platform::sudo sysctl -w kern.watchdog=1
log::result $? "Auto recovery"

# -- Boot & Login ----------------------------------------------------------
platform::sudo systemsetup -setremotelogin on
platform::sudo nvram AutoBoot=%03
log::result $? "Boot & login"

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
