# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

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

# brew when available, else a prebuilt GitHub-release binary (see the helper).
install::release_binary "ast-grep" "ast-grep" "ast-grep/ast-grep" \
  "https://github.com/ast-grep/ast-grep/releases/download/@TAG@/app-@ARCH_GNU@-unknown-linux-gnu.zip"
install::release_binary "shfmt" "shfmt" "mvdan/sh" \
  "https://github.com/mvdan/sh/releases/download/@TAG@/shfmt_@TAG@_linux_@ARCH_DEB@"
install::release_binary "actionlint" "actionlint" "rhysd/actionlint" \
  "https://github.com/rhysd/actionlint/releases/download/@TAG@/actionlint_@VER@_linux_@ARCH_DEB@.tar.gz"
install::release_binary "zizmor" "zizmor" "zizmorcore/zizmor" \
  "https://github.com/zizmorcore/zizmor/releases/download/@TAG@/zizmor-@ARCH_GNU@-unknown-linux-gnu.tar.gz"

# trash: macos-trash provides `trash` (real Finder Trash). On Linux, link the
# repo's shim, which moves paths to $TRASH_DIR (default ~/.local/share/Trash/files).
if platform::is_osx; then
  install::package "macos-trash" "macos-trash"
else
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$DOTFILES/modules/claude/bin/trash" "$HOME/.local/bin/trash"
  log::success "trash (mv to \${TRASH_DIR:-~/.local/share/Trash/files})"
fi
