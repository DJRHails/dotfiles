# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

if cmd_exists cloudflared; then
  log::success "cloudflared already installed"
else
  CODENAME=""
  if cmd_exists lsb_release; then
    CODENAME="$(lsb_release -cs 2>/dev/null)"
  fi
  if [ -z "$CODENAME" ] && [ -r /etc/os-release ]; then
    CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")"
  fi
  if [ -z "$CODENAME" ]; then
    log::error "cloudflared: could not determine distro codename (lsb_release / /etc/os-release)"
    return 1
  fi
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | platform::sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $CODENAME main" \
    | platform::sudo tee /etc/apt/sources.list.d/cloudflared.list
  platform::sudo apt-get update -qq
  platform::sudo apt-get install -y cloudflared
  log::result $? "cloudflared installed"
fi
