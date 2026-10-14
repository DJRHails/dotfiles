#!/bin/bash
#
# Manual counterpart to the daily auto-update (update.sh, which is silent and
# only writes to its log): pull ~/.files now, with git's output on the terminal.
#
# Same safety as the unattended pull — fast-forward only, so a diverged branch
# is left for a human — and the same submodule step afterwards
# (sync-submodules.sh): clean, detached submodules follow their bumped pins,
# and any with local work is skipped with the reason printed.
dotfiles::update() {
  local dir="${DOTFILES:-$HOME/.files}"
  git -C "$dir" pull --ff-only --prune --no-recurse-submodules &&
    bash "$dir/modules/dotfiles-autoupdate/sync-submodules.sh" "$dir"
}
