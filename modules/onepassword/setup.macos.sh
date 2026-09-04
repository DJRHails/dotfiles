#!/usr/bin/env bash
. "$DOTFILES/scripts/core/main.sh"

# The SSH agent and the CLI integration are signed settings: 1Password discards
# hand edits to settings.json at launch, so both can only be turned on inside the
# app (Settings → Developer). This reports what is still off, then checks that
# every vault the agent config names is visible to the signed-in account — an
# unresolvable vault makes the agent silently offer no keys at all.
agent_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
agent_config="$HOME/.config/1Password/ssh/agent.toml"

if [ -S "$agent_sock" ]; then
  log::success "1Password SSH agent"
else
  log::info "Turn on the SSH agent: 1Password → Settings → Developer → 'Use the SSH agent'"
  return 0
fi

if [ -n "$(op account list 2>/dev/null)" ]; then
  log::success "1Password CLI integration"
else
  log::info "Turn on CLI integration: 1Password → Settings → Developer → 'Integrate with 1Password CLI'"
  return 0
fi

while read -r vault; do
  if op vault get "$vault" >/dev/null 2>&1; then
    log::success "agent config vault '$vault' resolves"
  else
    log::warning "agent config names vault '$vault', which this account cannot see"
  fi
done < <(sed -n 's/^vault[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$agent_config")

unset agent_sock agent_config
