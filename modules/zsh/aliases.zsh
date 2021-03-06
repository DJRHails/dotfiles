#!/bin/bash

alias reload!='exec -l zsh' # Allows for a full reload?
alias reset!="cd $DOTFILES && ./bootstrap.sh"
alias cls='clear' # Good 'ol Clear Screen command

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias open='platform::open'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias -g G="| grep" # Grep pipe shortcut
alias -g C="| cb" # Copy to clipboard (see functions/cb)
alias -g "?"="| fzf" # Pipe to fuzzy search e.g (la ?)
alias -g NF='./*(oc[1])' # Points to newest file/dir e.g. tar xf NF; cd NF

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias h="cd ~"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias cd..="cd .."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias -s git="git clone"
alias -s {md,txt}="atom"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias t1="tree -L 1 -I 'node_modules|cache'"
alias t2="tree -L 2 -I 'node_modules|cache'"
alias t3="tree -L 3 -I 'node_modules|cache'"
alias te='tree'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias :q="exit"
alias q="exit"
alias ch="history -c && > ~/.bash_history"
alias path='printf "%b\n" "${PATH//:/\\n}"'
alias ll="ls -l"
alias la="ls -la"
alias m="man"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# TODO(DJRHails):
# https://github.com/nikitavoloboev/dotfiles/blob/master/zsh/functions/fzf-functions.zsh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Project and Site shortcuts
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# > echo "$(grab $PROJECTS)"
# > grab "dir1:dir2"
# dir1/
# dir2/
# dir1/content.txt
# ...
grab() {
  { fd . $(echo ${1//:/ }); echo "${1//:/\n}" } | fzf -1 -q ${2:-""}
}

# > jump $PROJECTS
jump() {
  local dest="$(grab $@)"
  if [[ -d $dest ]]; then
    cd "$dest"
  elif [[ -f $dest ]]; then
    cd "$(dirname $dest)"
  fi
}

p() { jump $PROJECTS $1 }
s() { jump $SITES $1 }
j() { jump $JUMPPOINTS $1 }

fzf-down() {
  fzf --height 50% "$@" --border
}

# Month <-> number.
months() {
  locale mon | sed 's/;/\n/g' | awk '{ print NR, $1 }' | fzf-down
}

# Get box characters
boxchars() {
  echo "┌ ─ ┐ │ └ ─ ┘" | tr ' ' '\n' | fzf-down | cb
}

# Search in path
fpath() {
  echo "${PATH//:/\\n}" | fzf-down
}

fenv() {
  env | fzf-down
}

fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')

  if [ "x$pid" != "x" ]
  then
    echo $pid | xargs kill -${1:-9}
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


# Gets the current ip address
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"

# List of commands I use most often, these are candidates for aliases
candidates() {
  history | \
    awk '{CMD[$2]++;count++;}END { for (a in CMD)print CMD[a] " " CMD[a]/count*100 "% " a;}' | \
    grep -v "./" | \
    column -c3 -s " " -t | \
    sort -nr | nl |  head -n 20
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
