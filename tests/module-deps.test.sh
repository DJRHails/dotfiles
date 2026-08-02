#!/usr/bin/env bash
# Behavior suite for deps::resolve_order (scripts/deps.sh).
# Self-contained: `bash tests/module-deps.test.sh`. Exits non-zero on failure.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# Fixture repo: a modules/ tree we control, with the real scripts/ borrowed so
# deps.sh finds core/main.sh at $DOTFILES/scripts/core/main.sh.
mkdir -p "$work/modules"
ln -s "$repo_root/scripts" "$work/scripts"
export DOTFILES="$work"
# shellcheck source=/dev/null
. "$work/scripts/deps.sh"

fails=0
check() {
  if [[ $2 == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

check_contains() {
  if [[ $3 == *"$2"* ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected to contain [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

# module <name> [dep...] — (re)create a fixture module declaring those deps.
module() {
  local name="$1"
  shift
  mkdir -p "$work/modules/$name"
  rm -f "$work/modules/$name/deps.conf"
  [ $# -gt 0 ] && printf '%s\n' "$@" > "$work/modules/$name/deps.conf"
  return 0
}

# Resolved install order as a space-separated list of module names; empty when
# resolution fails. Log output is discarded so only the order is compared.
resolve() {
  scanned_valid_modules=()
  local name
  for name in "$@"; do scanned_valid_modules+=("$DOTFILES/modules/$name"); done
  deps::resolve_order >/dev/null 2>&1 || return 1
  local names=()
  for name in "${scanned_valid_modules[@]}"; do names+=("${name##*/}"); done
  printf '%s\n' "${names[*]}"
}

# Everything the resolver logged (log::error writes to stdout, like the rest of
# the log:: helpers), for asserting on failure diagnostics.
resolve_error() {
  scanned_valid_modules=()
  local name
  for name in "$@"; do scanned_valid_modules+=("$DOTFILES/modules/$name"); done
  deps::resolve_order 2>&1 || true
}

# -- ordering ---------------------------------------------------------------

module alpha
module beta
module gamma
check no-deps-preserves-order "alpha beta gamma" "$(resolve alpha beta gamma)"
check no-deps-preserves-explicit-order "gamma alpha beta" "$(resolve gamma alpha beta)"

# A declared dependency installs first, even when it wasn't selected.
module beta alpha
check dep-pulled-in "alpha beta" "$(resolve beta)"
check dep-reordered "alpha beta" "$(resolve beta alpha)"

# Transitive chains resolve end to end.
module gamma beta
check transitive-chain "alpha beta gamma" "$(resolve gamma)"

# A module reachable by two paths appears exactly once.
module delta alpha beta
check diamond-no-duplicates "alpha beta delta" "$(resolve delta)"

# Unrelated modules keep their selection order around a forced one.
module epsilon
check independent-order-kept "epsilon alpha beta" "$(resolve epsilon beta)"

# Comments and blank lines are ignored, as in symlinks.conf.
mkdir -p "$work/modules/zeta"
printf '# leading comment\n\nalpha  # trailing comment\n\n' > "$work/modules/zeta/deps.conf"
check comments-ignored "alpha zeta" "$(resolve zeta)"

# An empty selection is a no-op, not an error.
check empty-selection "" "$(resolve)"

# -- failures ---------------------------------------------------------------

# A dependency that names no module is a typo, not a module to skip.
module orphan does-not-exist
check unknown-dep-fails "1" "$(resolve orphan >/dev/null 2>&1; echo $?)"
check_contains unknown-dep-message "depends on 'does-not-exist'" "$(resolve_error orphan)"

# Self-cycle.
module narcissus narcissus
check self-cycle-fails "1" "$(resolve narcissus >/dev/null 2>&1; echo $?)"
check_contains self-cycle-message "narcissus -> narcissus" "$(resolve_error narcissus)"

# Two-node cycle.
module castor pollux
module pollux castor
check two-cycle-fails "1" "$(resolve castor >/dev/null 2>&1; echo $?)"
check_contains two-cycle-message "castor -> pollux -> castor" "$(resolve_error castor)"

# Three-node cycle entered through a tail: the report names the cycle, not the
# tail that merely leads into it.
module tail_in one
module one two
module two three
module three one
check tail-cycle-fails "1" "$(resolve tail_in >/dev/null 2>&1; echo $?)"
check_contains tail-cycle-message "one -> two -> three -> one" "$(resolve_error tail_in)"
check_contains tail-cycle-lists-unresolvable "unresolvable modules:" "$(resolve_error tail_in)"

# A cycle anywhere in the graph fails the whole run — no partial ordering.
module bystander
check cycle-fails-whole-run "1" "$(resolve bystander castor >/dev/null 2>&1; echo $?)"

# -- the repo's own module tree ---------------------------------------------

# Every module resolved together: catches a cycle or a typo in a real deps.conf.
mapfile -t all_modules < <(cd "$repo_root/modules" && ls -1)
real_order="$(DOTFILES="$repo_root" resolve "${all_modules[@]}")"
check real-tree-resolves "0" "$([ -n "$real_order" ] && echo 0 || echo 1)"

# Position of a module in real_order, or -1.
index_of() {
  local needle="$1" i=0 name
  # shellcheck disable=SC2086  # deliberate word splitting on the order list
  for name in $real_order; do
    [ "$name" = "$needle" ] && { echo "$i"; return; }
    ((i++))
  done
  echo -1
}
before() {
  [ "$(index_of "$1")" -lt "$(index_of "$2")" ] && echo 0 || echo 1
}
check real-rust-before-git "0" "$(before rust git)"
check real-git-before-python "0" "$(before git python)"
check real-python-before-zellij "0" "$(before python zellij)"
check real-go-before-claude "0" "$(before go claude)"
check real-node-before-pi "0" "$(before node pi)"
# git appends a `Host github.com` block to ~/.ssh/config; linking the ssh
# module afterwards backs that file aside and loses the block.
check real-ssh-before-git "0" "$(before ssh git)"
check real-ssh-before-gpu-vm "0" "$(before ssh gpu-vm)"
check real-node-before-claude "0" "$(before node claude)"
check real-python-before-claude "0" "$(before python claude)"
check real-python-before-agents "0" "$(before python agents)"

# Selecting claude alone drags in its whole transitive closure.
claude_closure="$(DOTFILES="$repo_root" resolve claude)"
for required in go node python git rust ssh; do
  check "claude-closure-has-$required" "0" \
    "$([[ " $claude_closure " == *" $required "* ]] && echo 0 || echo 1)"
done

# The --cli set gains exactly the modules its dependencies require.
cli_order="$(DOTFILES="$repo_root" resolve zsh ssh git python node piknik tailscale \
  cloudflared claude agents dotfiles-autoupdate)"
check cli-pulls-in-rust-and-go "0" \
  "$([[ $cli_order == *rust* && $cli_order == *go* ]] && echo 0 || echo 1)"

if ((fails == 0)); then
  printf 'all passed\n'
  exit 0
fi
printf '%s failed\n' "$fails"
exit 1
