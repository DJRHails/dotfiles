#!/bin/bash

alias venv='python3 -m venv .venv && source .venv/bin/activate && pip install --upgrade pip setuptools -q'
alias ae='source .venv/bin/activate'
alias de='deactivate'

function aenv() {
  local env_file=${1:-'.env'}
  if [ -f $env_file ]; then
    export $(echo $(cat $env_file | sed 's/#.*//g'| xargs) | envsubst)
  else
    echo "File '$env_file' not found"
  fi
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