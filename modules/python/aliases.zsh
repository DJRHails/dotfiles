#!/bin/bash

alias venv='python3 -m venv .venv && source .venv/bin/activate && pip install --upgrade pip setuptools -q'
alias ae='source .venv/bin/activate'
alias de='deactivate'

function aenv() {
  local env_file="${1:-.env}"
  local env_files=("$env_file")
  local last_file=""
  while [[ $env_file && $last_file != $env_file ]]; do
    last_file=$env_file
    env_file=$(echo "$env_file" | sed 's/\.[^.]*$//')
    env_files+=("$env_file")
  done
  for (( i=${#env_files[@]}; i>=1; i-- )); do
    local file=${env_files[i]}

    if [[ -z "$file" ]]; then
      continue
    fi

    if [[ -f "$file" ]]; then
      export $(echo $(cat $file | sed 's/#[^'\''"]*$//g'| xargs) | envsubst)
      echo "Sourced '$file'"
    else
      echo "File '$file' not found"
    fi
  done
}

function poetry() {
  # if POETRY_DONT_LOAD_ENV is *not* set, then load .env if it exists
  if [[ -z "$POETRY_DONT_LOAD_ENV" && -f .env ]]; then
      echo 'Loading .env environment variables…'
      export $(grep -v '^#' .env | tr -d ' ' | xargs)
      command poetry "$@"
      unset $(grep -v '^#' .env | sed -E 's/(.*)=.*/\1/' | xargs)
  else
      command poetry "$@"
  fi
}