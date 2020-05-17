. "$DOTFILES/scripts/core/main.sh"

# Install
# Check version exisiting
if ! platform::command_exists "cargo"
then
  curl https://sh.rustup.rs -sSf | sh
  log::result $? "Install rust, cargo"
fi
