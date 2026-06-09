#!/usr/bin/env bash

zshrc::hash () {
  if platform::command_exists sha256sum; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi | cut -d' ' -f1
}

setup_zshrc () {
  local ZSHRC=modules/zsh/zshrc
  local STAMP=modules/zsh/.zshrc.sha256

  # Refuse to wipe manual edits. A zshrc differing from the recorded hash of
  # its last render was edited by hand; template-only changes still
  # regenerate freely. Legacy zshrcs without a stamp fall back to comparing
  # against a fresh render of the current template.
  if [ -f "$ZSHRC" ] && [ "${FORCE_ZSHRC:-}" != 1 ]; then
    local edited=false
    if [ -f "$STAMP" ]; then
      [ "$(zshrc::hash "$ZSHRC")" != "$(cat "$STAMP")" ] && edited=true
    elif ! sed -e "s+DOTFILES_+$DOTFILES+g" modules/zsh/zshrc.tmpl | cmp -s - "$ZSHRC"; then
      edited=true
    fi
    if $edited; then
      log::error "$ZSHRC has local edits; not overwriting" \
        '(move them to ~/.zshrc.local or rerun with FORCE_ZSHRC=1)'
      return 1
    fi
  fi

  sed -e "s+DOTFILES_+$DOTFILES+g" \
    modules/zsh/zshrc.tmpl > "$ZSHRC"

  log::result $? 'generated modules/zsh/zshrc'
  zshrc::hash "$ZSHRC" > "$STAMP"

  local LOCAL_ZSHRC=modules/zsh/zshrc.local
  if ! [ -f $LOCAL_ZSHRC ]
  then
    local project_dir sites_dir
    project_dir="$( [ -d /workspace ] && echo /workspace || echo "$HOME/projects" )"
    sites_dir="$HOME/sites"

    feedback::ask " - Where are you going to store your projects?" "$project_dir"
    project_dir="$(feedback::get_answer)"

    feedback::ask " - Where are you going to store your sites?" "$sites_dir"
    sites_dir="$(feedback::get_answer)"

    sed -e "s+PROJECT_ROOT+$project_dir+g;s+SITES_ROOT+$sites_dir+g" \
      $LOCAL_ZSHRC.tmpl > $LOCAL_ZSHRC

    log::result $? 'generated modules/zsh/zshrc.local'
  fi
}

. "$DOTFILES/scripts/core/main.sh"
setup_zshrc
