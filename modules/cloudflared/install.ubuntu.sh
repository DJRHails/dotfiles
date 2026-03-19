. "$DOTFILES/scripts/core/main.sh"

if cmd_exists cloudflared; then
  log::success "cloudflared already installed"
else
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | platform::sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
    | platform::sudo tee /etc/apt/sources.list.d/cloudflared.list
  platform::sudo apt-get update -qq
  platform::sudo apt-get install -y cloudflared
  log::result $? "cloudflared installed"
fi
