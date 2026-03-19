. "$DOTFILES/scripts/core/main.sh"

if [ -d "/Applications/Tailscale.app" ]; then
  log::success "Tailscale app"
else
  brew install --cask tailscale
  log::result $? "Tailscale app"
fi

if cmd_exists tailscale; then
  log::success "Tailscale CLI"
else
  brew install tailscale
  log::result $? "Tailscale CLI"
fi

# Enable IP forwarding for exit node capability
if grep -q "net.inet.ip.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
  log::success "IP forwarding already configured"
else
  echo 'net.inet.ip.forwarding=1' | platform::sudo tee -a /etc/sysctl.conf > /dev/null
  echo 'net.inet6.ip6.forwarding=1' | platform::sudo tee -a /etc/sysctl.conf > /dev/null
  log::result $? "IP forwarding configured in /etc/sysctl.conf"
fi
# Apply at runtime if not already active
if [ "$(sysctl -n net.inet.ip.forwarding 2>/dev/null)" != "1" ]; then
  platform::sudo sysctl -w net.inet.ip.forwarding=1 2>/dev/null
  platform::sudo sysctl -w net.inet6.ip6.forwarding=1 2>/dev/null
fi

# Launch Tailscale daemon
if ! tailscale status &>/dev/null; then
  open /Applications/Tailscale.app
  log::info "Launched Tailscale.app, waiting for daemon..."
  for i in $(seq 1 10); do
    tailscale status &>/dev/null && break
    sleep 1
  done
fi
