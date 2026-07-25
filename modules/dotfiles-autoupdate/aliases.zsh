#!/bin/bash
#
# Manual counterpart to the daily auto-update (update.sh, which is silent and
# only writes to its log): pull ~/.files now, with git's output on the terminal.
#
# Same safety as the unattended pull — fast-forward only, so a diverged branch
# is left for a human — and skips submodules, whose pinned state is managed
# separately (`git submodule update` follows a bumped pin).
alias dotfiles::update='git -C "${DOTFILES:-$HOME/.files}" pull --ff-only --prune --no-recurse-submodules'
