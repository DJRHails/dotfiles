#!/usr/bin/env bash

##? Setup shared agent config (AGENTS.md, skills)
##?
##? Provides AGENTS.md and skills/ shared across coding agents (Claude Code, pi).
##? symlinks.conf links into ~/.agents/, ~/.claude/, and ~/.pi/agent/.

. "$DOTFILES/scripts/core/main.sh"

# Ensure target directories exist (symlinks.conf populates them)
mkdir -p ~/.agents ~/.claude ~/.pi/agent

log::success "Shared agent config setup complete"
