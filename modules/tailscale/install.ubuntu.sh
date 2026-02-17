. "$DOTFILES/scripts/core/main.sh"

if cmd_exists tailscale; then
  log::success "Tailscale already installed"
else
  curl -fsSL https://tailscale.com/install.sh | sh
  log::result $? "Tailscale installed"
fi

# Enable IP forwarding for exit node capability
if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.d/99-tailscale.conf 2>/dev/null; then
  echo 'net.ipv4.ip_forward = 1' | platform::sudo tee -a /etc/sysctl.d/99-tailscale.conf
  echo 'net.ipv6.conf.all.forwarding = 1' | platform::sudo tee -a /etc/sysctl.d/99-tailscale.conf
  platform::sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
  log::result $? "IP forwarding enabled for exit node"
else
  log::success "IP forwarding already configured"
fi

# Enable and start the tailscale daemon
if platform::command_exists systemctl; then
  platform::sudo systemctl enable --now tailscaled
  log::result $? "tailscaled service started"
fi
