#!/usr/bin/env bash

##? Setup shared agent config (AGENTS.md, skills)
##?
##? Provides AGENTS.md and skills/ shared across coding agents (Claude Code, pi).
##? symlinks.conf links into ~/.agents/, ~/.claude/, and ~/.pi/agent/.

. "$DOTFILES/scripts/core/main.sh"

# Ensure target directories exist (symlinks.conf populates them)
mkdir -p ~/.agents ~/.claude ~/.pi/agent

# Link machine-local skills (skills.local.conf) into skills/ when their
# targets exist on this machine. Linked names are gitignored, so hosts
# without a target stay clean instead of carrying broken symlinks.
while read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  skill_name=${line%% -> *}
  skill_target=${line#* -> }
  skill_target=${skill_target/#\~/$HOME}
  if [ -e "$skill_target" ]; then
    ln -sfn "$skill_target" "$DOTFILES/modules/agents/skills/$skill_name"
    log::success "linked local skill '$skill_name'"
  else
    log::warning "local skill '$skill_name' skipped ($skill_target not on this machine)"
  fi
done < "$DOTFILES/modules/agents/skills.local.conf"

log::success "Shared agent config setup complete"
