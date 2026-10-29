#!/usr/bin/env zsh
# Behavior suite for the agent_summary preload export in modules/zsh/zshenv.
# Self-contained: `zsh -f tests/no-agent-summary.test.zsh`. Exits non-zero on failure.
set -u

script_dir="${0:A:h}"
dotfiles="${script_dir:h}"
zshenv="$dotfiles/modules/zsh/zshenv"
hook="$dotfiles/modules/claude/scripts/no-agent-summary.js"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    print "ok   $1"
  else
    print "FAIL $1: expected [$2] got [$3]"
    (( fails++ ))
  fi
}

# Source zshenv in a fresh non-rc shell with DOTFILES pointed at $1 and BUN_OPTIONS preset to $2
# ("unset" leaves it unset), then print the resulting BUN_OPTIONS.
bun_options_after() {
  local root=$1 preset=$2
  local set_preset="BUN_OPTIONS=${(q)preset}"
  [[ $preset == unset ]] && set_preset="unset BUN_OPTIONS"
  DOTFILES=$root zsh -f -c "$set_preset; source ${(q)zshenv}; print -r -- \${BUN_OPTIONS-unset}"
}

check fresh "--preload=$hook" "$(bun_options_after "$dotfiles" unset)"
check appends-to-existing "--smol --preload=$hook" "$(bun_options_after "$dotfiles" --smol)"
# A nested shell (claude's Bash tool, a subshell) inherits the export and must not add it twice.
check idempotent "--preload=$hook" "$(bun_options_after "$dotfiles" "--preload=$hook")"
check no-hook-file-leaves-env "--smol" "$(bun_options_after "$work" --smol)"

# The preload's Claude-Code-only gate keys on the install path, so check it activates under the
# claude actually installed here. Skipped where claude is absent.
if (( $+commands[claude] )); then
  log="$work/hook.log"
  BUN_OPTIONS="--preload=$hook" CC_AGENT_SUMMARY_LOG=$log claude --version >/dev/null
  check activates-in-claude "preload active mode=off" "$(grep -o 'preload active mode=off' "$log")"
else
  print "skip activates-in-claude: no claude on PATH"
fi

(( fails == 0 )) || { print "$fails failure(s)"; exit 1; }
print "all passed"
