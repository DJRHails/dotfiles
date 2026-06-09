# FZF Configuration
# =================

# Check if fzf is installed
if ! command -v fzf &> /dev/null; then
  return
fi

# Core FZF settings
export FZF_DEFAULT_OPTS="
  --height 50%
  --layout=reverse
  --border rounded
  --info=inline
  --margin=1
  --padding=1
  --bind 'ctrl-/:toggle-preview'
  --bind 'ctrl-y:execute-silent(echo -n {2..} | cb)+abort'
  --bind 'ctrl-a:select-all'
  --bind 'ctrl-d:deselect-all'
  --preview-window=right:50%:wrap
"

# Use fd if available, otherwise fall back to find
if command -v fd &> /dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --strip-cwd-prefix --hidden --follow --exclude .git'
fi

# CTRL-T: Paste selected files into command line
export FZF_CTRL_T_OPTS="
  --preview 'command -v bat &>/dev/null && bat -n --color=always {} 2>/dev/null || cat {} 2>/dev/null || tree -C {} 2>/dev/null'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'
"

# ALT-C: cd into selected directory
export FZF_ALT_C_OPTS="
  --preview '(tree -C {} 2>/dev/null || ls -1A {}) | head -200'
"

# CTRL-R: Search history
export FZF_CTRL_R_OPTS="
  --preview 'echo {}'
  --preview-window down:3:wrap
  --bind 'ctrl-y:execute-silent(echo -n {2..} | cb)+abort'
"

# Completion trigger (default is **)
export FZF_COMPLETION_TRIGGER='~~'

# Enable fzf keybindings and completions
# Debian/Ubuntu package locations
if [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
  source /usr/share/doc/fzf/examples/key-bindings.zsh
fi
if [[ -f /usr/share/doc/fzf/examples/completion.zsh ]]; then
  source /usr/share/doc/fzf/examples/completion.zsh
fi

# Homebrew locations (macOS)
if [[ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh" ]]; then
  source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh"
fi
if [[ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh" ]]; then
  source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh"
fi

# Git install location
[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh

# ===== Enhanced FZF Functions =====

# fzf git log - browse commits
fgl() {
  git log --graph --color=always \
    --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
  fzf --ansi --no-sort --reverse --tiebreak=index \
    --bind "ctrl-m:execute:
      (grep -o '[a-f0-9]\{7\}' | head -1 |
      xargs -I % sh -c 'git show --color=always % | less -R') << 'FZF-EOF'
      {}
FZF-EOF"
}

# fzf git branch - checkout branch
fgb() {
  local branches branch
  branches=$(git branch --all | grep -v HEAD) &&
  branch=$(echo "$branches" |
           fzf -d $(( 2 + $(wc -l <<< "$branches") )) +m) &&
  git checkout $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
}

# fzf git stash - browse and apply stashes
fgs() {
  local stash
  stash=$(git stash list | fzf --reverse -d: --preview 'git stash show --color=always -p {1}') &&
  git stash apply $(echo "$stash" | cut -d: -f1)
}

# fzf man pages
fman() {
  man -k . | fzf --prompt='Man> ' --preview 'echo {} | awk "{print \$1}" | xargs man' | awk '{print $1}' | xargs man
}

# fzf npm scripts
fnpm() {
  local script
  script=$(cat package.json | jq -r '.scripts | keys[]' | fzf --preview 'cat package.json | jq -r ".scripts.{}"')
  [[ -n "$script" ]] && npm run "$script"
}

# Interactive cd with preview
fcd() {
  local dir
  dir=$(find ${1:-.} -path '*/\.*' -prune -o -type d -print 2>/dev/null | fzf +m --preview '(tree -C {} 2>/dev/null || ls -1A {}) | head -100') &&
  cd "$dir"
}

# Edit file with fzf
fe() {
  local file
  file=$(fzf --preview 'command -v bat &>/dev/null && bat -n --color=always {} || cat {}')
  [[ -n "$file" ]] && ${EDITOR:-vim} "$file"
}

# Search and edit with ripgrep + fzf
frg() {
  local file line
  read -r file line <<< $(rg --line-number --no-heading "$@" | fzf -d: --preview 'bat --color=always --highlight-line {2} {1}' | awk -F: '{print $1, $2}')
  [[ -n "$file" ]] && ${EDITOR:-vim} "$file" +$line
}
