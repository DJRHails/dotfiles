# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Linux node comes from the NodeSource apt repo (modules/node), whose global
# prefix is system-owned — npm -g needs sudo there, like the node module's own
# pnpm fallback. macOS (brew) keeps a user-writable node bin dir.
if ! platform::command_exists "pi"; then
  log::execute "$(platform::sudo_prefix)npm install -g @earendil-works/pi-coding-agent" \
    "pi-coding-agent"
elif npm ls -g @mariozechner/pi-coding-agent > /dev/null 2>&1; then
  # The @mariozechner name is deprecated on npm and receives no new releases.
  sudo_npm="$(platform::sudo_prefix)npm"
  log::execute \
    "$sudo_npm uninstall -g @mariozechner/pi-coding-agent && $sudo_npm install -g @earendil-works/pi-coding-agent" \
    "pi-coding-agent (migrate to @earendil-works)"
else
  log::success "pi-coding-agent"
fi

# Install pi extensions
if platform::command_exists "pi"; then
  # Canonical package set (mirrors modules/pi/settings.json `packages`).
  log::execute \
    "pi install git:github.com/DJRHails/pi-interactive-subagents" \
    "pi-interactive-subagents"

  log::execute \
    "pi install git:github.com/DJRHails/pi-smart-sessions" \
    "pi-smart-sessions"

  log::execute \
    "pi install npm:pi-multi-pass" \
    "pi-multi-pass"

  log::execute \
    "pi install git:github.com/DJRHails/pi-cc-patch" \
    "pi-cc-patch"

  log::execute \
    "pi install npm:@ff-labs/pi-fff" \
    "pi-fff"

  log::execute \
    "pi install npm:@narumitw/pi-goal" \
    "pi-goal"
fi
