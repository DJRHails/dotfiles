. "$DOTFILES/scripts/core/main.sh"

install_keybase() {
  if cmd_exists keybase; then
    log::success "Keybase already installed"
    return 0
  fi

  local tmp_deb="/tmp/keybase_amd64.deb"
  curl -fsSL https://prerelease.keybase.io/keybase_amd64.deb -o "$tmp_deb"
  platform::sudo dpkg -i "$tmp_deb" || platform::sudo apt-get install -f -y
  rm -f "$tmp_deb"
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
