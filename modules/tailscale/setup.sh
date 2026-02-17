. "$DOTFILES/scripts/core/main.sh"

# Connect and advertise as exit node
if tailscale status 2>&1 | grep -q "Logged out"; then
  log::info "Run 'tailscale up --advertise-exit-node' to connect and advertise as exit node"
else
  platform::sudo tailscale up --advertise-exit-node
  log::result $? "Tailscale connected as exit node"
fi
