# shellcheck shell=bash
. "$DOTFILES/scripts/core/main.sh"

# Socket Firewall Free (sfw) — wraps a package-manager invocation and blocks
# known-malicious packages at the network layer before they download
# (npm/pnpm/yarn, pip/uv, cargo). No brew formula or apt package exists, so
# both platforms take the prebuilt release binary. It lands in ~/.local/bin
# (user-writable) so the daily autoupdate can replace it without sudo —
# Socket drops support for old binaries, so a stale sfw eventually stops
# working (see ensure_sfw_fresh in modules/dotfiles-autoupdate/update.sh).
if platform::command_exists sfw; then
  log::success "sfw ($(sfw --version 2>/dev/null))"
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
  if curl -fsSL "$sfw_url" -o "$sfw_tmp"; then
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$sfw_tmp" "$HOME/.local/bin/sfw"
    log::result $? "sfw ($("$HOME/.local/bin/sfw" --version 2>/dev/null))"
  else
    log::error "sfw: download failed ($sfw_url)"
  fi
  rm -f "$sfw_tmp"
fi
