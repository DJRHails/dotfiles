. "$DOTFILES/scripts/core/main.sh"

set -euo pipefail

ZELLIJ_VERSION="${ZELLIJ_VERSION:-0.44.3}"

case "$(uname -m)" in
  x86_64)  ZELLIJ_ARCH="x86_64-unknown-linux-musl" ;;
  aarch64) ZELLIJ_ARCH="aarch64-unknown-linux-musl" ;;
  *) echo "[zellij] unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

ZELLIJ_TARBALL="zellij-${ZELLIJ_ARCH}.tar.gz"
ZELLIJ_URL="https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/${ZELLIJ_TARBALL}"

TMPDIR_ZELLIJ=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ZELLIJ"' EXIT

wget -q --show-progress -O "$TMPDIR_ZELLIJ/${ZELLIJ_TARBALL}" "$ZELLIJ_URL"
tar -xzf "$TMPDIR_ZELLIJ/${ZELLIJ_TARBALL}" -C "$TMPDIR_ZELLIJ"
platform::sudo install -m 0755 "$TMPDIR_ZELLIJ/zellij" /usr/local/bin/zellij
