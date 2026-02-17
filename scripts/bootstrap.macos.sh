#!/usr/bin/env bash
# macOS-specific bootstrap: Xcode CLT, Homebrew, modern Bash.
# Sourced by bootstrap.sh — runs BEFORE the Bash 4+ gate.
# Must avoid Bash 4+ features (associative arrays, etc.)

# Install Xcode Command Line Tools if missing
if ! xcode-select -p &>/dev/null; then
  log::info "Installing Xcode Command Line Tools..."
  xcode-select --install
  log::info "Waiting for Xcode CLT installation to complete..."
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  log::success "Xcode Command Line Tools installed"
else
  log::success "Xcode Command Line Tools already installed"
fi

# Install Homebrew if missing
if ! platform::command_exists brew; then
  log::info "Homebrew not found, installing..."
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
