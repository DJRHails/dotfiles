#!/usr/bin/env bash

if ! ${DOT_MAIN_SOURCED:-false} ; then
   source "${DOTFILES}/scripts/core/platform.sh"
   source "${DOTFILES}/scripts/core/log.sh"
   source "${DOTFILES}/scripts/core/filesystem.sh"
   source "${DOTFILES}/scripts/core/feedback.sh"

   # Requires platform, log
   source "${DOTFILES}/scripts/core/install.sh"
   readonly DOT_MAIN_SOURCED=true
fi

if ${DOT_TRACE:-false}; then
   set -x
fi
