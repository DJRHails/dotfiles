. "$DOTFILES/scripts/core/main.sh"

if [ -d "/Applications/Tailscale.app" ]; then
  log::success "Tailscale"
else
  brew install --cask tailscale
  log::result $? "Tailscale"
fi

# Enable IP forwarding for exit node capability
if ! sysctl -n net.inet.ip.forwarding 2>/dev/null | grep -q "1"; then
  echo 'net.inet.ip.forwarding=1' | platform::sudo tee -a /etc/sysctl.conf
  echo 'net.inet6.ip6.forwarding=1' | platform::sudo tee -a /etc/sysctl.conf
  platform::sudo sysctl -w net.inet.ip.forwarding=1
  platform::sudo sysctl -w net.inet6.ip6.forwarding=1
  log::result $? "IP forwarding enabled for exit node"
else
  log::success "IP forwarding already configured"
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
