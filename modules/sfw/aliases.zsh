# Route package-fetching commands through Socket Firewall (sfw), which blocks
# known-malicious packages before they download. Only subcommands that can
# fetch artifacts are wrapped: sfw adds ~0.5s per invocation, too much for hot
# paths like `uv run` / `cargo build` — the documented leak is that their
# auto-fetch after a manual lockfile/manifest edit bypasses sfw (an `add`/
# `sync`/`fetch` first stays covered). Functions, not aliases, so each wrapper
# can dispatch per-subcommand. No recursion: sfw is an external process, so
# the `npm` it spawns resolves from PATH, where shell functions don't exist.
# Scripts and CI are untouched (zshrc is interactive-only); bypass one call
# with `command npm …`.
if (( $+commands[sfw] )); then
  # First token that is not an option or a cargo +toolchain — `npm --prefix p
  # install` and `cargo +nightly add` must still match their fetching verb.
  _sfw_subcmd() {
    local a
    for a in "$@"; do
      [[ "$a" == [-+]* ]] || { print -r -- "$a"; return; }
    done
  }
  npm() {
    # The full `npm help install` alias family — the typo-shaped ones
    # (isnt…/udpate) are exactly what interactive muscle memory produces.
    case "$(_sfw_subcmd "$@")" in
      install | i | in | ins | inst | insta | instal | isnt | isnta | isntal | isntall | add | \
        ci | install-test | it | install-ci-test | cit | sit | update | up | upgrade | udpate | \
        dedupe | ddp | audit | exec | x | init | create) sfw npm "$@" ;;
      *) command npm "$@" ;;
    esac
  }
  pnpm() {
    case "$(_sfw_subcmd "$@")" in
      install | i | add | update | up | upgrade | dlx | create | import | fetch | patch)
        sfw pnpm "$@" ;;
      *) command pnpm "$@" ;;
    esac
  }
  yarn() {
    # The empty pattern: a bare (or flags-only) `yarn` is an install. `global`
    # covers global add.
    case "$(_sfw_subcmd "$@")" in
      "" | install | add | up | upgrade | upgrade-interactive | dlx | create | global)
        sfw yarn "$@" ;;
      *) command yarn "$@" ;;
    esac
  }
  pip() {
    case "$(_sfw_subcmd "$@")" in
      install | download | wheel) sfw pip "$@" ;;
      *) command pip "$@" ;;
    esac
  }
  pip3() {
    case "$(_sfw_subcmd "$@")" in
      install | download | wheel) sfw pip3 "$@" ;;
      *) command pip3 "$@" ;;
    esac
  }
  uv() {
    case "$(_sfw_subcmd "$@")" in
      add | sync | pip | tool | venv | lock) sfw uv "$@" ;;
      *) command uv "$@" ;;
    esac
  }
  cargo() {
    case "$(_sfw_subcmd "$@")" in
      add | install | update | fetch) sfw cargo "$@" ;;
      *) command cargo "$@" ;;
    esac
  }
  # npx/uvx exist to fetch-and-run arbitrary packages — always wrapped.
  npx() { sfw npx "$@"; }
  uvx() { sfw uvx "$@"; }
fi
