# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

PIKNIK_VERSION="0.10.1"
# sha256 of the release tarball; the project publishes no checksum asset, so
# this was computed once from the canonical GitHub release download.
PIKNIK_SHA256="b429f333dd3b0849b40237e522a2f1db4b3b69c64023b7a9e8150664df39bb95"
PIKNIK_TARBALL="piknik-linux_x86_64-${PIKNIK_VERSION}.tar.gz"
PIKNIK_URL="https://github.com/jedisct1/piknik/releases/download/${PIKNIK_VERSION}/${PIKNIK_TARBALL}"

TMPDIR_PIKNIK=$(mktemp -d)
piknik_rc=1
if wget -q -O "${TMPDIR_PIKNIK}/${PIKNIK_TARBALL}" "$PIKNIK_URL" \
  && echo "${PIKNIK_SHA256}  ${TMPDIR_PIKNIK}/${PIKNIK_TARBALL}" | sha256sum -c - >/dev/null 2>&1; then
  tar -xzf "${TMPDIR_PIKNIK}/${PIKNIK_TARBALL}" -C "${TMPDIR_PIKNIK}"
  platform::sudo install -m 0755 "${TMPDIR_PIKNIK}/linux-x86_64/piknik" /usr/local/bin/piknik
  piknik_rc=$?
  log::result $piknik_rc "piknik ${PIKNIK_VERSION}"
else
  log::error "piknik: download failed or sha256 mismatch for ${PIKNIK_TARBALL} (expected ${PIKNIK_SHA256})"
fi
rm -r "${TMPDIR_PIKNIK}"
[ "$piknik_rc" -eq 0 ]  # propagate install status to bootstrap's log::result
