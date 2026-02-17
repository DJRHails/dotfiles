. "$DOTFILES/scripts/core/main.sh"

install::cask "Tailscale" "tailscale"

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
