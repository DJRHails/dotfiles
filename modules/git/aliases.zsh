alias g="git"

alias gs='git status -sb' # upgrade your git if -sb breaks for you. it's fun.
alias gl='git pull --prune'
alias glog="git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias gp='git push origin HEAD'

# Remove `+` and `-` from start of diff lines; just rely upon color.
alias gd='git diff --color | sed "s/^\([^-+ ]*\)[-+ ]/\\1/" | less -r'

# Fuzzy search to checkout branches
alias fb='git checkout `git branch | fzf | sed s:remotes/origin/::g`'

ghopen() {
  open "https://github.com/$1"
}

genignore() {
  local language=$1

  # fetch the gitignore file from gitignore.io
  curl -L -s "https://www.gitignore.io/api/$language" >> .gitignore
}

# Specifies the clipboard output format is html
# commonly used with cbh | 2md
alias cbh='cb -t html'