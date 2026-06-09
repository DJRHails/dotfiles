# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

set -euo pipefail

ZELLIJ_VERSION="${ZELLIJ_VERSION:-0.44.3}"

# sha256 of the extracted `zellij` binary, from the official per-target
# *.sha256sum release assets for v0.44.3. Override ZELLIJ_SHA256 together
# with ZELLIJ_VERSION.
case "$(uname -m)" in
  x86_64)
    ZELLIJ_ARCH="x86_64-unknown-linux-musl"
    ZELLIJ_SHA256="${ZELLIJ_SHA256:-397481870c4fc3bae646cd7613cde3a1cebdc204558a6cb9a7c603d4c852fc90}"
    ;;
  aarch64)
    ZELLIJ_ARCH="aarch64-unknown-linux-musl"
    ZELLIJ_SHA256="${ZELLIJ_SHA256:-439ed44da5df3cd70e578dc4aef5a67dc7b81eabdddec27969d84a6be380b2f0}"
    ;;
  *) echo "[zellij] unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

ZELLIJ_TARBALL="zellij-${ZELLIJ_ARCH}.tar.gz"
ZELLIJ_URL="https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/${ZELLIJ_TARBALL}"

TMPDIR_ZELLIJ=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ZELLIJ"' EXIT

wget -q --show-progress -O "$TMPDIR_ZELLIJ/${ZELLIJ_TARBALL}" "$ZELLIJ_URL"
tar -xzf "$TMPDIR_ZELLIJ/${ZELLIJ_TARBALL}" -C "$TMPDIR_ZELLIJ"
if ! echo "${ZELLIJ_SHA256}  ${TMPDIR_ZELLIJ}/zellij" | sha256sum -c - >/dev/null 2>&1; then
  echo "[zellij] sha256 mismatch for ${ZELLIJ_TARBALL} (expected ${ZELLIJ_SHA256})" >&2
  exit 1
fi
platform::sudo install -m 0755 "$TMPDIR_ZELLIJ/zellij" /usr/local/bin/zellij

# humane CLI — auto-attach.zsh / mosh-zellij.zsh use `humane id` for readable session names.
if platform::command_exists uv; then
  command -v humane >/dev/null 2>&1 || uv tool install humane
fi
