. "$DOTFILES/scripts/core/main.sh"

# Install Rust via rustup
if ! platform::command_exists "cargo"
then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  log::result $? "Install rust, cargo"
fi

# Cargo packages
install::with "cargo" "prek" "prek" ""
install::with "cargo" "worktrunk" "worktrunk" ""
install::with "cargo" "cargo-deny" "cargo-deny" ""
install::with "cargo" "cargo-careful" "cargo-careful" ""
