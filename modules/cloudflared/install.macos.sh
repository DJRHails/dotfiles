. "$DOTFILES/scripts/core/main.sh"

if cmd_exists cloudflared; then
  log::success "cloudflared"
else
  brew install cloudflared
  log::result $? "cloudflared"
fi
