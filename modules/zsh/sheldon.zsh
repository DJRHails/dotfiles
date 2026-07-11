#!/usr/bin/env zsh

# Provide a compdef stub so plugins loaded before compinit can register completions
if (( ! $+functions[compdef] )); then
  typeset -ga __deferred_compdefs
  compdef() { __deferred_compdefs+=("${(j: :)@}") }
fi

# Cached: `sheldon source` spawns a ~90ms subprocess but its output only
# changes when the binary or plugins.toml does.
if (( $+commands[sheldon] )); then
  _cached_eval -d "${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml" sheldon source
else
  print -u2 "warning: sheldon not installed; zsh plugins skipped"
fi
