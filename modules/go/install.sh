# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Go toolchain: brew when available, else the official go.dev tarball into
# ~/.local/go with go/gofmt symlinked into ~/.local/bin (on PATH, no sudo).
# apt's golang-go is too stale (1.22 on Ubuntu 24.04) to be useful.
# Idempotent: no-op when `go` is already on PATH. `go install` binaries land in
# ~/go/bin, which modules/zsh/zshenv adds to PATH; dotfiles-managed go tools
# (install::go_tool) are pinned to ~/.local/bin instead.
install::go_toolchain() {
  if platform::command_exists go; then
    log::success "go ($(go version | awk '{print $3}'))"
    return 0
  fi

  if platform::command_exists brew; then
    log::execute "brew install go" "go"
    return $?
  fi

  local ver os arch
  ver="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
  if [ -z "$ver" ]; then
    log::error "go: could not resolve latest version from go.dev"
    return 1
  fi

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$(uname -m)" in
    x86_64 | amd64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *) log::error "go: unsupported architecture $(uname -m)"; return 1 ;;
  esac

  local -r url="https://go.dev/dl/${ver}.${os}-${arch}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"
  if ! curl -fsSL "$url" -o "$tmp/go.tar.gz"; then
    log::error "go: download failed ($url)"
    rm -rf "$tmp"
    return 1
  fi

  rm -rf "$HOME/.local/go"
  mkdir -p "$HOME/.local" "$HOME/.local/bin"
  tar -xzf "$tmp/go.tar.gz" -C "$HOME/.local"
  rm -rf "$tmp"
  ln -sfn "$HOME/.local/go/bin/go" "$HOME/.local/bin/go"
  ln -sfn "$HOME/.local/go/bin/gofmt" "$HOME/.local/bin/gofmt"
  log::result $? "go ($ver)"
}

install::go_toolchain
