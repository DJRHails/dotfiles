# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Linux node comes from the NodeSource apt repo (modules/node), whose global
# prefix is system-owned — npm -g needs sudo there, like the node module's own
# pnpm fallback. macOS (brew) keeps a user-writable node bin dir.
if platform::command_exists "pi"; then
  log::success "pi-coding-agent"
elif platform::is_osx; then
  log::execute "npm install -g @earendil-works/pi-coding-agent" \
    "pi-coding-agent"
else
  log::execute "sudo npm install -g @earendil-works/pi-coding-agent" \
    "pi-coding-agent"
fi

# Install pi extensions
if platform::command_exists "pi"; then
  log::execute \
    "pi install git:github.com/DJRHails/pi-interactive-subagents" \
    "pi-interactive-subagents"

  log::execute \
    "pi install git:github.com/pasky/chrome-cdp-skill" \
    "chrome-cdp-skill"

  log::execute \
    "pi install git:github.com/DJRHails/pi-smart-sessions" \
    "pi-smart-sessions"

  log::execute \
    "pi install npm:pi-multi-pass" \
    "pi-multi-pass"

  log::execute \
    "pi install npm:pi-web-access" \
    "pi-web-access"

  log::execute \
    "pi install npm:pi-subagents" \
    "pi-subagents"

  log::execute \
    "pi install npm:@ff-labs/pi-fff" \
    "pi-fff"
fi
