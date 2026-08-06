#!/usr/bin/env bash
# Behavior suite for scripts/link.sh.
# Self-contained: `bash tests/link-symlinks.test.sh`. Exits non-zero on failure.
#
# link::prune_stale deletes files, so a regression here is destructive rather
# than merely wrong. It exists to clear links left by an earlier revision of a
# conf, and it identifies drift as "a link in a declared parent directory that
# points into this module but is not itself declared". Once a module can carry
# both `symlinks.conf` and `symlinks.<os>.conf`, that definition is only safe if
# the two are pruned against the union of their declarations — pruned singly,
# each conf's links look like drift to the other.
set -u

# prune_stale uses associative arrays, so the code under test needs bash 4+ —
# the same floor bootstrap.sh enforces. macOS still ships 3.2 as /bin/bash and
# the hooks invoke a bare `bash`, so find a newer one and re-exec rather than
# skipping: a suite that silently passes on the maintainer's machine guards
# nothing.
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [ -x "$candidate" ]; then
      exec "$candidate" "${BASH_SOURCE[0]}" "$@"
    fi
  done
  echo "SKIP link-symlinks: needs bash 4+, found only ${BASH_VERSION:-?}" >&2
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

# link.sh resolves helpers through $DOTFILES and destinations through $HOME;
# both are redirected into the sandbox so nothing touches the real dotfiles.
DOTFILES="$repo_root"
export DOTFILES
# shellcheck source=/dev/null
. "$repo_root/scripts/core/main.sh"
# shellcheck source=/dev/null
. "$repo_root/scripts/link.sh"

# Read by link::file via dynamic scoping; without them it prompts for every
# pre-existing destination.
# shellcheck disable=SC2034
overwrite_all=false backup_all=false skip_all=false

module="$work/module"
HOME="$work/home"
export HOME

setup_module() {
  rm -rf -- "$module" "$HOME"
  mkdir -p "$module" "$HOME"
  printf 'base\n' > "$module/base.conf.file"
  printf 'osonly\n' > "$module/os.conf.file"
  # Both confs declare into the SAME destination directory — the arrangement
  # that made single-conf pruning delete the sibling's link.
  printf 'base.conf.file -> ~/.config/app/base\n' > "$module/symlinks.conf"
  printf 'os.conf.file -> ~/.config/app/os\n' > "$module/symlinks.macos.conf"
}

link_target() { readlink "$1" 2> /dev/null || printf '(missing)'; }

# --- both confs link, and neither prunes the other --------------------------
setup_module
link::extract_and_link "$module/symlinks.conf" "$module/symlinks.macos.conf" > /dev/null 2>&1

check "base conf destination is linked" \
  "$module/base.conf.file" "$(link_target "$HOME/.config/app/base")"
check "os conf destination is linked" \
  "$module/os.conf.file" "$(link_target "$HOME/.config/app/os")"

# --- re-running is idempotent: the links survive a second pass ---------------
link::extract_and_link "$module/symlinks.conf" "$module/symlinks.macos.conf" > /dev/null 2>&1

check "base link survives a second run" \
  "$module/base.conf.file" "$(link_target "$HOME/.config/app/base")"
check "os link survives a second run" \
  "$module/os.conf.file" "$(link_target "$HOME/.config/app/os")"

# --- a link this module no longer declares is still pruned ------------------
printf 'dropped\n' > "$module/dropped.file"
ln -s "$module/dropped.file" "$HOME/.config/app/dropped"
link::extract_and_link "$module/symlinks.conf" "$module/symlinks.macos.conf" > /dev/null 2>&1

check "undeclared link into the module is pruned" \
  "(missing)" "$(link_target "$HOME/.config/app/dropped")"

# --- a link owned by something else is left alone ---------------------------
printf 'other\n' > "$work/foreign.file"
ln -s "$work/foreign.file" "$HOME/.config/app/foreign"
link::extract_and_link "$module/symlinks.conf" "$module/symlinks.macos.conf" > /dev/null 2>&1

check "link pointing outside the module is untouched" \
  "$work/foreign.file" "$(link_target "$HOME/.config/app/foreign")"

# --- destinations containing spaces round-trip ------------------------------
# The macOS VS Code path is "~/Library/Application Support/...".
setup_module
printf 'base.conf.file -> ~/Library/Application Support/App/settings\n' \
  > "$module/symlinks.macos.conf"
link::extract_and_link "$module/symlinks.conf" "$module/symlinks.macos.conf" > /dev/null 2>&1

check "destination with spaces is linked" \
  "$module/base.conf.file" \
  "$(link_target "$HOME/Library/Application Support/App/settings")"

if ((fails)); then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
