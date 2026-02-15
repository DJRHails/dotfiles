#!/bin/bash
# Hook: Notify when Claude needs attention

. "$DOTFILES/scripts/core/main.sh"

platform::notify "Claude Code" "Claude needs your attention"

exit 0
