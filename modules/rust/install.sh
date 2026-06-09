# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Install Rust via rustup (-y: no prompt under non-interactive bootstrap;
# --no-modify-path: PATH is handled below and by modules/rust/source.zsh)
if ! platform::command_exists "cargo"
then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  log::result $? "Install rust, cargo"
fi

# rustup installs into ~/.cargo/bin; with --no-modify-path nothing edits the
# live PATH, so ensure the cargo installs below resolve during a fresh bootstrap.
[[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]] && export PATH="$HOME/.cargo/bin:$PATH"

# Cargo packages (worktrunk's binary is `wt`)
install::cargo_tool "prek" "prek"
install::cargo_tool "worktrunk" "wt" "worktrunk"
install::cargo_tool "cargo-deny" "cargo-deny"
install::cargo_tool "cargo-careful" "cargo-careful"
