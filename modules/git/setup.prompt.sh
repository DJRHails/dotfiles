#!/usr/bin/env bash

prompt::author_name() {
  if [[ -z $GIT_AUTHOR_NAME ]]; then
    feedback::ask ' - What is your github author username?'
    GIT_AUTHOR_NAME=$(feedback::get_answer)
  fi
}

prompt::author_email() {
  if [[ -z $GIT_AUTHOR_EMAIL ]]; then
    feedback::ask ' - What is your github author email?'
    GIT_AUTHOR_EMAIL=$(feedback::get_answer)
  fi
}

prompt::author() {
  prompt::author_name
  prompt::author_email
}
