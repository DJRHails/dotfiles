. "$DOTFILES/scripts/core/main.sh"

install_tailscale() {
  if cmd_exists tailscale; then
    log::success "Tailscale already installed"
    return 0
  fi

  curl -fsSL https://tailscale.com/install.sh | sh
  log::result $? "Tailscale installed"
}

setup_tailscale() {
  # Enable IP forwarding for exit node capability
  if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.d/99-tailscale.conf 2>/dev/null; then
    echo 'net.ipv4.ip_forward = 1' | platform::sudo tee -a /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | platform::sudo tee -a /etc/sysctl.d/99-tailscale.conf
    platform::sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
    log::result $? "IP forwarding enabled for exit node"
  else
    log::success "IP forwarding already configured"
  fi

  # Start tailscale and advertise as exit node
  if tailscale status 2>&1 | grep -q "Logged out"; then
    log::info "Run 'tailscale up --advertise-exit-node' to connect and advertise as exit node"
  else
    platform::sudo tailscale up --advertise-exit-node
    log::result $? "Tailscale connected as exit node"
  fi
}

install_tailscale
setup_tailscale
