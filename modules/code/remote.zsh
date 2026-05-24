# Host-aware `code`: opens Cursor/VS Code on a UI-capable host, with
# Remote-SSH pointed back at the current host's filesystem.
#
# On the UI host itself, falls through to the real `code` binary
# (on macOS that's typically Cursor's wrapper at /usr/local/bin/code).
#
# Depends on helpers from modules/ssh/lib.zsh: ssh::self, ssh::ui_host,
# ssh::open_url, path::abs.

code() {
  local ui self scheme abs
  ui=$(ssh::ui_host)
  self=$(ssh::self)

  if [[ "$ui" == "$self" ]]; then
    command code "$@"
    return $?
  fi

  scheme="${CODE_URL_SCHEME:-cursor}"
  abs=$(path::abs "${1:-.}")
  ssh::open_url "$ui" "${scheme}://vscode-remote/ssh-remote+${self}${abs}"
}
