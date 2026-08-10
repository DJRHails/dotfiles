# shellcheck shell=bash
# llm-save-merge: LLM 3-way merge for VS Code editor-vs-disk save conflicts.
# Installs/upgrades the extension from its GitHub release into every VS Code
# CLI on this host: the desktop `code` binary and any Remote-SSH vscode-server.
# The remote-cli `code` shim is skipped — it needs a live VSCODE_IPC_HOOK_CLI.
# https://github.com/DJRHails/vscode-llm-save-merge
# shellcheck source=/dev/null
. "$DOTFILES/scripts/core/main.sh"

code::llm_save_merge_clis() {
  local desktop server
  desktop="$(command -v code 2>/dev/null || true)"
  case "$desktop" in
  '' | */remote-cli/*) ;; # no desktop CLI, or the IPC-bound Remote-SSH shim
  *) printf '%s\n' "$desktop" ;;
  esac
  # Every server version shares ~/.vscode-server/extensions; one CLI suffices.
  for server in "$HOME"/.vscode-server/cli/servers/Stable-*/server/bin/code-server; do
    if [ -x "$server" ]; then
      printf '%s\n' "$server"
      break
    fi
  done
}

code::llm_save_merge_latest_tag() {
  # Buffer the API response before matching: `grep -m1` on a live pipe closes
  # it on the first match and curl dies with SIGPIPE.
  local api
  api="$(curl -fsSL \
    "https://api.github.com/repos/DJRHails/vscode-llm-save-merge/releases/latest" \
    2>/dev/null)" || return 1
  printf '%s' "$api" | grep -m1 '"tag_name"' |
    sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'
}

code::install_llm_save_merge() {
  local tag ver
  tag="$(code::llm_save_merge_latest_tag)" || true
  if [ -z "$tag" ]; then
    log::error "llm-save-merge: could not resolve the latest GitHub release"
    return 1
  fi
  ver="${tag#v}"

  local found=false vsix="" cli installed
  while IFS= read -r cli; do
    [ -n "$cli" ] || continue
    found=true
    installed="$("$cli" --list-extensions --show-versions 2>/dev/null |
      sed -n 's/^djrhails\.llm-save-merge@//p' | head -n1)"
    if [ "$installed" = "$ver" ]; then
      log::success "llm-save-merge $ver (${cli##*/})"
      continue
    fi
    if [ -z "$vsix" ]; then
      vsix="$(mktemp -d)/llm-save-merge-${ver}.vsix"
      if ! curl -fsSL -o "$vsix" \
        "https://github.com/DJRHails/vscode-llm-save-merge/releases/download/${tag}/llm-save-merge-${ver}.vsix"; then
        log::error "llm-save-merge: downloading the ${tag} vsix failed"
        return 1
      fi
    fi
    log::execute "'$cli' --install-extension '$vsix' --force" \
      "llm-save-merge $ver → ${cli##*/}"
  done < <(code::llm_save_merge_clis)

  if ! $found; then
    log::warning "llm-save-merge: no VS Code CLI on this host yet — connect once via Remote-SSH, then rerun the code module"
  fi
}

code::install_llm_save_merge
