. "$DOTFILES/scripts/core/main.sh"

# Verify daemon is reachable before proceeding
if ! tailscale status &>/dev/null; then
  log::warning "Tailscale service not running — start it manually, then run 'tailscale up --advertise-exit-node --accept-routes'"
  return 0
fi

# Connect and advertise as exit node
if tailscale status 2>&1 | grep -q "Logged out"; then
  log::info "Run 'tailscale up --advertise-exit-node --accept-routes' to connect and advertise as exit node"
else
  platform::sudo tailscale up --advertise-exit-node --accept-routes
  log::result $? "Tailscale connected as exit node"
fi
