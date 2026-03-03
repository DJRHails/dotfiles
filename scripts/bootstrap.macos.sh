#!/usr/bin/env bash
# macOS-specific bootstrap: Xcode CLT, Homebrew, modern Bash.
# Sourced by bootstrap.sh — runs BEFORE the Bash 4+ gate.
# Must avoid Bash 4+ features (associative arrays, etc.)

# Install Xcode Command Line Tools if missing.
# Avoid xcode-select --install which opens a GUI dialog and hangs
# over SSH. Use softwareupdate for headless installs instead.
if ! xcode-select -p &>/dev/null; then
  log::info "Installing Xcode Command Line Tools..."
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  CLT_LABEL=$(softwareupdate -l 2>/dev/null \
    | grep -o 'Label: Command Line Tools.*' \
    | head -1 \
    | sed 's/^Label: //')
  if [ -n "$CLT_LABEL" ]; then
    softwareupdate -i "$CLT_LABEL"
  else
    log::warning "No CLT package found via softwareupdate, trying xcode-select"
    xcode-select --install
    until xcode-select -p &>/dev/null; do sleep 5; done
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  log::success "Xcode Command Line Tools installed"
else
  log::success "Xcode Command Line Tools already installed"
fi

# Install Homebrew if missing
if ! platform::command_exists brew; then
  log::info "Homebrew not found, installing..."
  # Homebrew needs sudo to create /opt/homebrew. Prompt now so the
  # NONINTERACTIVE installer can use the cached credential.
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  log::success "Homebrew installed"
fi

# Ensure Homebrew is on PATH (ARM vs Intel prefix)
if [ -d /opt/homebrew ]; then
  HOMEBREW_PREFIX=/opt/homebrew
else
  HOMEBREW_PREFIX=/usr/local
fi
eval "$("${HOMEBREW_PREFIX}/bin/brew" shellenv)"
log::success "Homebrew on PATH (${HOMEBREW_PREFIX})"

brew update

# Upgrade Bash if system version is too old (< 4)
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  log::info "Bash ${BASH_VERSINFO:-unknown} is too old, installing modern Bash..."
  brew install bash
  log::success "Bash installed, re-executing with ${HOMEBREW_PREFIX}/bin/bash"
  exec "${HOMEBREW_PREFIX}/bin/bash" "$0" "${BOOTSTRAP_ARGS[@]}"
fi
