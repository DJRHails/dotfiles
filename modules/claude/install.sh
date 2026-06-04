# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Prefer Homebrew (macOS always; Linux too when Linuxbrew is present). Fall back
# to a prebuilt GitHub-release binary only when brew is unavailable — e.g. a bare
# Linux box where these tools have no apt package.
claude::install_tool() { # readable_name cmd repo url_template
  if platform::command_exists "$2"; then
    log::success "$1"
  elif platform::command_exists brew; then
    log::execute "brew install $2" "$1"
  else
    install::release_binary "$1" "$2" "$3" "$4"
  fi
}

install::package "jq" "jq"
install::package "ripgrep" "ripgrep"
install::package "shellcheck" "shellcheck"

# fd: apt ships it as `fd-find` (binary `fdfind`); expose the canonical `fd`.
if platform::is_osx; then
  install::package "fd" "fd"
else
  install::package "fd-find" "fd-find"
  platform::command_exists fd || platform::relink "fdfind" "fd"
fi

claude::install_tool "ast-grep" "ast-grep" "ast-grep/ast-grep" \
  "https://github.com/ast-grep/ast-grep/releases/download/@TAG@/app-@ARCH_GNU@-unknown-linux-gnu.zip"
claude::install_tool "shfmt" "shfmt" "mvdan/sh" \
  "https://github.com/mvdan/sh/releases/download/@TAG@/shfmt_@TAG@_linux_@ARCH_DEB@"
claude::install_tool "actionlint" "actionlint" "rhysd/actionlint" \
  "https://github.com/rhysd/actionlint/releases/download/@TAG@/actionlint_@VER@_linux_@ARCH_DEB@.tar.gz"
claude::install_tool "zizmor" "zizmor" "zizmorcore/zizmor" \
  "https://github.com/zizmorcore/zizmor/releases/download/@TAG@/zizmor-@ARCH_GNU@-unknown-linux-gnu.tar.gz"

# trash: macos-trash provides `trash` (real Finder Trash). On Linux, link the
# repo's shim, which moves paths to $TRASH_DIR (default /tmp/trash).
if platform::is_osx; then
  install::package "macos-trash" "macos-trash"
else
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$DOTFILES/modules/claude/bin/trash" "$HOME/.local/bin/trash"
  log::success "trash (mv to \${TRASH_DIR:-/tmp/trash})"
fi
