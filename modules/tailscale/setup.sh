. "$DOTFILES/scripts/core/main.sh"

# Ensure tailscale daemon is running
if ! tailscale status &>/dev/null; then
  if platform::is_osx; then
    open -a Tailscale
    log::info "Launched Tailscale.app, waiting for daemon..."
    for i in $(seq 1 10); do
      tailscale status &>/dev/null && break
      sleep 1
    done
  elif platform::command_exists systemctl; then
    platform::sudo systemctl enable --now tailscaled
    log::result $? "tailscaled service started"
  fi
fi

# Verify daemon is reachable before proceeding
if ! tailscale status &>/dev/null; then
  log::warning "Tailscale service not running — start it manually, then run 'tailscale up --advertise-exit-node'"
  return 0
fi

# Connect and advertise as exit node
if tailscale status 2>&1 | grep -q "Logged out"; then
  log::info "Run 'tailscale up --advertise-exit-node' to connect and advertise as exit node"
else
  platform::sudo tailscale up --advertise-exit-node
  log::result $? "Tailscale connected as exit node"
fi
