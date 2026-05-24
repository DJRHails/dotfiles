# Generic SSH/host helpers shared across dotfiles modules.
#
# Naming:
#   ssh::self      — the name this host advertises to a UI host's SSH
#   ssh::ui_host   — the first UI-capable host (cursor/vscode)
#   ssh::open_url  — `open <url>` on a remote macOS host
#   path::abs      — resolve an absolute path on the local FS
#
# Configuration (set in ~/.zshrc.local to override defaults):
#   CODE_UI_HOSTS   — array of UI-capable hosts, first wins. Default: (trifle)
#   CODE_LOCAL_HOST — override $(hostname -s) for ssh-remote+ identity
#   CODE_URL_SCHEME — cursor | vscode. Default: cursor

typeset -ga CODE_UI_HOSTS
[[ ${#CODE_UI_HOSTS[@]} -eq 0 ]] && CODE_UI_HOSTS=(trifle)

ssh::self() {
  echo "${CODE_LOCAL_HOST:-$(hostname -s)}"
}

ssh::ui_host() {
  local self h
  self=$(ssh::self)
  for h in "${CODE_UI_HOSTS[@]}"; do
    [[ "$h" == "$self" ]] && { echo "$self"; return; }
  done
  echo "${CODE_UI_HOSTS[1]}"
}

ssh::open_url() {
  local host="$1" url="$2"
  ssh "$host" "/usr/bin/open '$url'"
}

path::abs() {
  local t="${1:-.}"
  if [[ -d "$t" ]]; then
    (cd "$t" && pwd)
  elif [[ -e "$t" ]]; then
    echo "$(cd "$(dirname "$t")" && pwd)/$(basename "$t")"
  else
    echo "$(pwd)/$t"
  fi
}
