#!/usr/bin/env bash

prompt::author_name() {
  if [[ -z $GIT_AUTHOR_NAME ]]; then
    local default="DJRHails"
    if [ "$skipQuestions" = true ]; then
      GIT_AUTHOR_NAME="$default"
    else
      feedback::ask " - What is your github author username? [$default]"
      GIT_AUTHOR_NAME=$(feedback::get_answer)
      GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$default}"
    fi
  fi
}

prompt::author_email() {
  if [[ -z $GIT_AUTHOR_EMAIL ]]; then
    local default="hello@hails.info"
    if [ "$skipQuestions" = true ]; then
      GIT_AUTHOR_EMAIL="$default"
    else
      feedback::ask " - What is your github author email? [$default]"
      GIT_AUTHOR_EMAIL=$(feedback::get_answer)
      GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$default}"
    fi
  fi
}

prompt::author() {
  prompt::author_name
  prompt::author_email
}
