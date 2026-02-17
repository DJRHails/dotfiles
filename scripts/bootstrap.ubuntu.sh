#!/usr/bin/env bash
# Linux-specific bootstrap: refresh package cache, install essentials.
# Sourced by bootstrap.sh — runs BEFORE the Bash 4+ gate.
# Must avoid Bash 4+ features (associative arrays, etc.)

if platform::command_exists apt; then
  log::info "Refreshing apt package cache..."
  platform::sudo apt update -qq

  # Install essential build tools if missing
  for pkg in curl git build-essential; do
    if ! dpkg -s "$pkg" &>/dev/null; then
      log::info "Installing $pkg..."
      platform::sudo apt install -qqy "$pkg"
    fi
  done
  log::success "Essential packages available"
fi
