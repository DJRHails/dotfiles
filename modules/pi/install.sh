# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# npm -g installs to the configured prefix. Prefer a user-writable prefix
# (`npm config set prefix ~/.npm-global`, on PATH via modules/zsh/zshenv) so no
# sudo is needed; fall back to sudo only when the prefix is system-owned (e.g.
# a bare NodeSource install on Linux). `sudo npm` reads root's config, so mixing
# the two leaves divergent copies — /usr/bin/pi is shadowed by PATH order.
npm_prefix="$(npm config get prefix 2>/dev/null)"
if [[ -w "$npm_prefix" ]]; then
  sudo_npm="npm"
else
  sudo_npm="$(platform::sudo_prefix)npm"
fi

if ! platform::command_exists "pi"; then
  log::execute "$sudo_npm install -g @earendil-works/pi-coding-agent" \
    "pi-coding-agent"
elif npm ls -g @mariozechner/pi-coding-agent > /dev/null 2>&1; then
  # The @mariozechner name is deprecated on npm and receives no new releases.
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
