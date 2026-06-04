#!/usr/bin/env bash

install::with() {
  local -r PACKAGE_MANAGER="$1"
  local -r PACKAGE_READABLE_NAME="$2"
  local -r PACKAGE="$3"
  local EXTRA_ARGUMENTS="$4"
  
  # Inject extra arguments if not provided
  if [ -z "$EXTRA_ARGUMENTS" ]; then
    EXTRA_ARGUMENTS=$(platform::main_package_args)
  fi

  if ! platform::command_exists "$PACKAGE"; then
    log::execute "$PACKAGE_MANAGER install $EXTRA_ARGUMENTS $PACKAGE" "$PACKAGE_READABLE_NAME"
  else
    log::success "$PACKAGE_READABLE_NAME"
  fi
}

install::package_manager() {
  echo "$(platform::sudo_prefix)$(platform::main_package_manager)"
}

install::package() {
  install::with "$(install::package_manager)" "$1" "$2" "$3"
}

install::snap() {
  install::with "$(platform::sudo_prefix)snap" "$1" "$2" "$3"
}

install::cask() {
  install::with "brew" "$1" "$2" "$3" "--cask"
}

# Install a developer CLI tool, preferring Homebrew (macOS always; Linux only
# when Linuxbrew is present) and falling back to a prebuilt GitHub-release binary
# only when brew is unavailable — e.g. a bare Linux box where the tool has no apt
# package. URL_TEMPLATE may contain these placeholders, substituted before the
# fallback download:
#   @TAG@       full release tag       (e.g. v3.13.1)
#   @VER@       tag without leading v  (e.g. 3.13.1)
#   @ARCH_DEB@  amd64 | arm64          (Go / dpkg arch naming)
#   @ARCH_GNU@  x86_64 | aarch64       (Rust / GNU arch naming)
# TAG defaults to the repo's latest release; pass a 5th arg to pin it. .tar.gz
# and .zip assets are unpacked and CMD is located inside them; any other asset
# installs directly. Lands in ~/.local/bin (on PATH, no sudo). No-op if present.
install::release_binary() {
  local -r readable_name="$1"
  local -r cmd="$2"
  local -r repo="$3"
  local -r url_template="$4"
  local tag="${5:-}"

  if platform::command_exists "$cmd"; then
    log::success "$readable_name"
    return 0
  fi

  if platform::command_exists brew; then
    log::execute "brew install $cmd" "$readable_name"
    return $?
  fi

  if [ -z "$tag" ]; then
    tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
      | grep -m1 '"tag_name"' \
      | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')"
  fi
  if [ -z "$tag" ]; then
    log::error "$readable_name: could not resolve a release for $repo"
    return 1
  fi

  local arch_deb arch_gnu
  case "$(uname -m)" in
    x86_64 | amd64) arch_deb="amd64"; arch_gnu="x86_64" ;;
    aarch64 | arm64) arch_deb="arm64"; arch_gnu="aarch64" ;;
    *) log::error "$readable_name: unsupported architecture $(uname -m)"; return 1 ;;
  esac

  local url="$url_template"
  url="${url//@TAG@/$tag}"
  url="${url//@VER@/${tag#v}}"
  url="${url//@ARCH_DEB@/$arch_deb}"
  url="${url//@ARCH_GNU@/$arch_gnu}"

  local tmp archive src
  tmp="$(mktemp -d)"
  archive="$tmp/${url##*/}"

  if ! curl -fsSL "$url" -o "$archive"; then
    log::error "$readable_name: download failed ($url)"
    rm -rf "$tmp"
    return 1
  fi

  case "$archive" in
    *.tar.gz | *.tgz) tar -xzf "$archive" -C "$tmp" ;;
    *.zip)
      platform::command_exists unzip || install::package "unzip" "unzip"
      unzip -qo "$archive" -d "$tmp"
      ;;
    *) src="$archive" ;;
  esac
  [ -n "${src:-}" ] || src="$(find "$tmp" -type f -name "$cmd" -print -quit)"

  if [ -z "${src:-}" ] || [ ! -f "$src" ]; then
    log::error "$readable_name: '$cmd' not found in $url"
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$src" "$HOME/.local/bin/$cmd"
  local -r rc=$?
  rm -rf "$tmp"
  log::result "$rc" "$readable_name ($tag)"
  return "$rc"
}
