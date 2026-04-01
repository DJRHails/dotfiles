# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

if ! platform::command_exists "pi"; then
  log::execute "npm install -g @mariozechner/pi-coding-agent" \
    "pi-coding-agent"
else
  log::success "pi-coding-agent"
fi

# Install pi extensions
if platform::command_exists "pi"; then
  log::execute \
    "pi install git:github.com/HazAT/pi-interactive-subagents" \
    "pi-interactive-subagents"
fi
