# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Socket Firewall Free (sfw) — wraps a package-manager invocation and blocks
# known-malicious packages at the network layer before they download
# (npm/pnpm/yarn, pip/uv, cargo). No brew formula or apt package exists, so
# both platforms take the prebuilt release binary. It lands in ~/.local/bin
# (user-writable) so the daily autoupdate can replace it without sudo —
# Socket drops support for old binaries, so a stale sfw eventually stops
# working (see ensure_sfw_fresh in modules/dotfiles-autoupdate/update.sh).
# Hand-rolled rather than install::release_binary: the helper short-circuits
# to `brew install sfw` (no formula exists) and sfw's asset names mix GNU
# x86_64 with deb-style arm64, matching neither @ARCH_GNU@ nor @ARCH_DEB@.
if platform::command_exists sfw; then
  log::success "sfw ($(sfw --version 2>/dev/null))"
  [ -x "$HOME/.local/bin/sfw" ] ||
    log::warning "sfw resolves outside ~/.local/bin — the daily autoupdate refresh will not manage it"
else
  sfw_os="linux"
  platform::is_osx && sfw_os="macos"
  case "$(uname -m)" in
    x86_64 | amd64) sfw_arch="x86_64" ;;
    aarch64 | arm64) sfw_arch="arm64" ;;
    *)
      log::error "sfw: unsupported architecture $(uname -m)"
      return 1
      ;;
  esac

  sfw_url="https://github.com/SocketDev/sfw-free/releases/latest/download/sfw-free-${sfw_os}-${sfw_arch}"
  sfw_tmp="$(mktemp)"
  if ! curl -fsSL --connect-timeout 15 --max-time 300 "$sfw_url" -o "$sfw_tmp"; then
    log::error "sfw: download failed ($sfw_url)"
    rm -f "$sfw_tmp"
    return 1
  fi
  # Prove the download runs before installing it — a 200 with wrong content
  # must not be declared an installed firewall.
  chmod 0755 "$sfw_tmp"
  if ! "$sfw_tmp" --version > /dev/null 2>&1; then
    log::error "sfw: downloaded file is not a working sfw ($sfw_url)"
    rm -f "$sfw_tmp"
    return 1
  fi
  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$sfw_tmp" "$HOME/.local/bin/sfw"
  sfw_status=$?
  log::result $sfw_status "sfw ($("$HOME/.local/bin/sfw" --version 2>/dev/null))"
  rm -f "$sfw_tmp"
  [ $sfw_status -eq 0 ] || return 1
fi
