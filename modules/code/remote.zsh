# Host-aware `code`: opens Cursor/VS Code on a UI-capable host, with
# Remote-SSH pointed back at the current host's filesystem.
#
# On the UI host itself, falls through to the real `code` binary
# (on macOS that's typically Cursor's wrapper at /usr/local/bin/code).
#
# Depends on helpers from modules/ssh/lib.zsh: ssh::self, ssh::ui_host,
# ssh::open_url, path::abs.

code() {
  local ui self scheme abs root
  ui=$(ssh::ui_host)
  self=$(ssh::self)
  abs=$(path::abs "${1:-.}")
  root=$(git -C "${abs%/*}" rev-parse --show-toplevel 2>/dev/null)

  if [[ "$ui" == "$self" ]]; then
    if [[ -n "$root" && -f "$abs" && "$abs" != "$root" ]]; then
      command code "$root" --goto "$abs"
    else
      command code "$@"
    fi
    return $?
  fi

  scheme="${CODE_URL_SCHEME:-cursor}"
  if [[ -n "$root" && -f "$abs" && "$abs" != "$root" ]]; then
    ssh::open_url "$ui" "${scheme}://vscode-remote/ssh-remote+${self}${root}"
    ssh::open_url "$ui" "${scheme}://vscode-remote/ssh-remote+${self}${abs}"
  else
    ssh::open_url "$ui" "${scheme}://vscode-remote/ssh-remote+${self}${abs}"
  fi
}
