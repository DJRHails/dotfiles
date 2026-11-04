# Shared by both entry points, also sourceable independently in a fresh shell.
_session_resume_dir=${${(%):-%x}:A:h}

_agent_session_resume() {
  emulate -L zsh
  local target=$1 id=${2:-}
  [[ -n $id ]] || { print -u2 -- "$target::resume: usage: $target::resume <session-id-or-prefix> [options...]"; return 1; }
  shift 2
  local info dir claude_home codex_home
  info=$(python3 "$_session_resume_dir/convert.py" "$target" "$id") || return 1
  id=$(print -r -- "$info" | jq -r .id)
  dir=$(print -r -- "$info" | jq -r .cwd)
  claude_home=$(print -r -- "$info" | jq -r .claude_home)
  codex_home=$(print -r -- "$info" | jq -r .codex_home)

  cd -- "$dir" || return 1
  if [[ $target == codex ]]; then
    CODEX_HOME=$codex_home codex resume "$id" "$@"
  elif [[ $claude_home == $HOME/.claude-ant ]]; then
    claude::ant --resume "$id" "$@"
  elif [[ $claude_home == $HOME/.claude ]]; then
    # Claude reads ~/.claude.json (and the keychain login) only when
    # CLAUDE_CONFIG_DIR is unset; pointing it at ~/.claude starts a blank profile.
    (unset CLAUDE_CONFIG_DIR; claude --resume "$id" "$@")
  else
    CLAUDE_CONFIG_DIR=$claude_home claude --resume "$id" "$@"
  fi
}
