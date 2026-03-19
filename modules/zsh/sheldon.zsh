#!/usr/bin/env zsh

# Provide a compdef stub so plugins loaded before compinit can register completions
if (( ! $+functions[compdef] )); then
  typeset -ga __deferred_compdefs
  compdef() { __deferred_compdefs+=("${(j: :)@}") }
fi

eval "$(sheldon source)"
