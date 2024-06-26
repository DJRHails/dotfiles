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

mkcd() { [ -n "$1" ] && mkdir -p "$@" && cd "$1"; }

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias -s git="git clone"
alias -s {md,txt}="code"

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

# alias dsstore-clean='find . -type f -name .DS_Store -print0 | xargs -0 rm'

alias gs_recursive='find . -maxdepth 1 -mindepth 1 -type d -exec sh -c "echo {}; cd {}; git status -s; echo"  \;'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

alias rg='rg --smart-case'
alias rga='rg --smart-case --no-ignore --no-ignore-vcs --no-ignore-global'

rgw() {
  local query="$@" # Need to pass all args as one string, so local is necessary to coerce output into a string
  rg --smart-case -w --max-columns=100 --max-columns-preview "$query"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

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
  # Grab results order:
  # Return given results first
  # Then do MAX_DEPTH 4 pass to ensure we don't descend too far
  # as fd is a DFS
  { echo "${1//:/\n}"; fd . --max-depth 4 $(echo ${1//:/ }); fd . --min-depth 5 $(echo ${1//:/ }); } | fzf -1 -q ${2:-""}
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

# Get special characters
specialchars() {
  echo "$ ~ £ € \`" | tr ' ' '\n' | fzf-down | cb
}

emoji() {
  # If /tmp/emoji.json doesn't exist fetch it from github
  local EMOJI_PATH="/tmp/emoji.json"
  if [ ! -f $EMOJI_PATH ]; then
    curl -s https://raw.githubusercontent.com/omnidan/node-emoji/master/lib/emoji.json > $EMOJI_PATH
  fi

  LOOKUP_CMD="cat "$EMOJI_PATH" | jq -r '.[\"{}\"]'"
  KEYNAME=$(cat "$EMOJI_PATH" | jq -r 'keys[]' | fzf-down --preview $LOOKUP_CMD --preview-window=down:5%:wrap)
  # Extract emoji from JSON by keyname, trim newline and copy to clipboard
  cat "$EMOJI_PATH" | jq -r ".[\"$KEYNAME\"]" | tr -d '\n' | cb
  echo "\nCopied :$KEYNAME: to clipboard"
}

fsearch() {
  FZF_DEFAULT_COMMAND='rg --files --ignore-vcs --hidden' fzf-down | cb
}

# mnemonic: [F]uzzy [Path]
fpath() {
  # echo "${PATH//:/\\n}" | fzf-down
  local loc=$(echo $PATH | sed -e $'s/:/\\\n/g' | eval "fzf-down ${FZF_DEFAULT_OPTS} --header='[find:path]'")

  if [[ -d $loc ]]; then
    echo "$(rg --files $loc | rev | cut -d"/" -f1 | rev)" | eval "fzf-down ${FZF_DEFAULT_OPTS} --header='[find:exe] => ${loc}' >/dev/null"
    fpath
  fi
}

# mnemonic: [F]uzzy [Env]var
fenv() {
  env | fzf-down --header='[find:envvar]'
}

# mnemonic: [F]uzzy [Kill]
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m --header '[kill:pid]' | awk '{print $2}')

  if [ "x$pid" != "x" ]
  then
    echo $pid | xargs kill -${1:-9}
  fi
}

# mnemonic: [F]uzzy [Kill] [P]ort
# show output of "lsof -Pwni tcp", use [tab] to select one or multiple entries
fkillport() {
  local pid=$(lsof -Pwni tcp | sed 1d | eval "fzf ${FZF_DEFAULT_OPTS} -m --header='[kill:tcp]'" | awk '{print $2}')

  if [ "x$pid" != "x" ]
  then
    echo $pid | xargs kill -${1:-9}
    fkillport
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


# Gets the current ip address
alias ip="dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com"
alias ipv6="dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com"

# List of commands I use most often, these are candidates for aliases
candidates() {
  # alias profileme="history | awk '{print \$2}' | awk 'BEGIN{FS=\"|\"}{print \$1}' | sort | uniq -c | sort -n | tail -n 20 | sort -nr"
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
