# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

install_keybase() {
  if cmd_exists keybase; then
    log::success "Keybase already installed"
    return 0
  fi

  # Signed apt repo (Keybase code signing key) instead of an unverified .deb.
  curl -fsSL https://keybase.io/docs/server_security/code_signing_key.asc \
    | gpg --dearmor | platform::sudo tee /usr/share/keyrings/keybase.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/keybase.gpg arch=amd64] https://prerelease.keybase.io/deb stable main" \
    | platform::sudo tee /etc/apt/sources.list.d/keybase.list >/dev/null
  platform::sudo apt-get update -qq
  platform::sudo apt-get install -y keybase
  log::result $? "Keybase installed"
}

setup_keybase_mount() {
  # Enable redirector for /keybase mount
  platform::sudo mkdir -p /keybase
  platform::sudo chown $USER:$USER /keybase

  # Configure keybase for headless operation
  keybase config set mountdirdefault /keybase 2>/dev/null || true

  log::result $? "Keybase mount configured at /keybase"
}

install_keybase
setup_keybase_mount
