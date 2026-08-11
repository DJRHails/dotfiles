# Route package-fetching commands through Socket Firewall (sfw), which blocks
# known-malicious packages before they download. Only subcommands that can
# fetch artifacts are wrapped: sfw adds ~0.5s per invocation, too much for hot
# paths like `uv run` / `cargo build` — the documented leak is that their
# auto-fetch after a manual lockfile/manifest edit bypasses sfw (an `add`/
# `sync`/`fetch` first stays covered). Functions, not aliases: sfw execs the
# real binary from PATH, so there is no recursion. Scripts and CI are
# untouched (zshrc is interactive-only); bypass one call with `command npm …`.
if (( $+commands[sfw] )); then
  npm() {
    case "$1" in
      install | i | in | ins | add | ci | update | up | upgrade | audit | exec) sfw npm "$@" ;;
      *) command npm "$@" ;;
    esac
  }
  pnpm() {
    case "$1" in
      install | i | add | update | up | dlx | import | fetch | patch) sfw pnpm "$@" ;;
      *) command pnpm "$@" ;;
    esac
  }
  yarn() {
    # A bare `yarn` is an install.
    if (( $# == 0 )) || [[ "$1" == (install|add|up|upgrade|dlx) ]]; then
      sfw yarn "$@"
    else
      command yarn "$@"
    fi
  }
  pip() {
    case "$1" in
      install | download | wheel) sfw pip "$@" ;;
      *) command pip "$@" ;;
    esac
  }
  uv() {
    case "$1" in
      add | sync | pip | tool | venv | lock) sfw uv "$@" ;;
      *) command uv "$@" ;;
    esac
  }
  cargo() {
    case "$1" in
      add | install | update | fetch) sfw cargo "$@" ;;
      *) command cargo "$@" ;;
    esac
  }
  # npx/uvx exist to fetch-and-run arbitrary packages — always wrapped.
  npx() { sfw npx "$@"; }
  uvx() { sfw uvx "$@"; }
fi
