# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

install::snap "Visual Studio Code" "code" "--classic"

. "$DOTFILES/modules/code/llm-save-merge.sh"
