#!/bin/bash

alias reload!='. ~/.zshrc'
alias reset!="cd $DOTFILES && ./bootstrap.sh"
alias cls='clear' # Good 'ol Clear Screen command

alias h="cd ~"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias cd..="cd .."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias :q="exit"
alias q="exit"
alias ch="history -c && > ~/.bash_history"
alias path='printf "%b\n" "${PATH//:/\\n}"'
alias ll="ls -l"
alias la="ls -la"
alias m="man"

# Gets the current ip address
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"

# Month <-> number.
months() {
  locale mon | sed 's/;/\n/g' | awk '{ print NR, $1 }' | fzf
}

# fdfind -> fd as short binary is taken
alias fd="fdfind"

# Project and Site shortcuts
p() {
  cd $(fd . $(echo "${PROJECTS//:/ }") | fzf -1 -q ${1:-""})
}

s() {
  cd $(fd . $(echo "${SITES//:/ }") | fzf -1 -q ${1:-""})
}

# Capture takes over the std ouput of a process
capture() {
    sudo dtrace -p "$1" -qn '
        syscall::write*:entry
        /pid == $target && arg0 == 1/ {
            printf("%s", copyinstr(arg1, arg2));
        }
    '
}
