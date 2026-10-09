#!/usr/bin/env bash
# Behavior suite for modules/release-age.
# Self-contained: `bash tests/release-age.test.sh`. Exits non-zero on failure.
#
# The age gate is a security control with a quiet failure mode: a setup.sh that
# skips a tool, or a value that drifts away from 7 days in one of six different
# units, leaves installs ungated while the module still looks applied. So
# setup.sh runs here against stub npm/pnpm binaries that record every call, and
# each symlinked file is checked for the literal 7-day value in its own unit.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
module="$repo_root/modules/release-age"

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
check_contains() {
  if [[ $3 == *"$2"* ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected to contain [%s] got [%s]\n' "$1" "$2" "$3"
    ((fails++))
  fi
}

# -- stub package managers ----------------------------------------------------
# Each stub answers `--version`, `config get <key>` and `config set …` the way
# the real tool does, keeps its config file where $*_STUB_RC points, and appends
# every invocation to $*_STUB_LOG so the suite can count writes. npm prints
# `null` for an unset key and pnpm prints `undefined`, as the real ones do.
mkdir -p "$work/bin" "$work/bin-no-npm"
cat >"$work/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NPM_STUB_LOG"
case "$1" in
  --version) echo "$NPM_STUB_VERSION" ;;
  config)
    case "$2" in
      get)
        if [ "$3" = userconfig ]; then echo "$NPM_STUB_RC"
        elif [ -f "$NPM_STUB_RC" ] && grep -q "^$3=" "$NPM_STUB_RC"; then sed -n "s/^$3=//p" "$NPM_STUB_RC"
        else echo null; fi ;;
      set) printf '%s\n' "$3" >> "$NPM_STUB_RC" ;;
    esac ;;
esac
EOF
cat >"$work/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PNPM_STUB_LOG"
case "$1" in
  --version) echo "$PNPM_STUB_VERSION" ;;
  config)
    case "$2" in
      get)
        if [ "$3" = globalconfig ]; then echo "$PNPM_STUB_RC"
        elif [ -f "$PNPM_STUB_RC" ] && grep -q "^$3=" "$PNPM_STUB_RC"; then sed -n "s/^$3=//p" "$PNPM_STUB_RC"
        else echo undefined; fi ;;
      set) shift 2; [ "$1" = -g ] && shift; printf '%s=%s\n' "$1" "$2" >> "$PNPM_STUB_RC" ;;
    esac ;;
esac
EOF
chmod +x "$work/bin/npm" "$work/bin/pnpm"
ln -s "$work/bin/pnpm" "$work/bin-no-npm/pnpm"

# run_setup <state> [stub-bin-dir] — source setup.sh the way bootstrap does (in
# a subshell with $DOTFILES set), with only the stubs and the system bin dirs
# on PATH so the real npm/pnpm can never answer. Reusing a <state> name reruns
# against the files the previous run left. Prints the exit code; the run's
# output lands in <state>/out.
run_setup() {
  local state="$work/$1" bin="${2:-$work/bin}"
  mkdir -p "$state"
  touch "$state/npm.log" "$state/pnpm.log"
  (
    export NPM_STUB_RC="$state/npmrc" NPM_STUB_LOG="$state/npm.log"
    export NPM_STUB_VERSION="${NPM_STUB_VERSION:-11.19.0}"
    export PNPM_STUB_RC="$state/pnpmrc" PNPM_STUB_LOG="$state/pnpm.log"
    export PNPM_STUB_VERSION="${PNPM_STUB_VERSION:-10.32.1}"
    export PATH="$bin:/usr/bin:/bin" DOTFILES="$repo_root"
    # shellcheck source=/dev/null
    . "$module/setup.sh"
  ) >"$state/out" 2>&1
  echo $?
}
writes() { grep -c '^config set' "$work/$1/$2.log"; }

# -- a fresh host: both keys written, once, in the user/global location -------
check fresh-exit "0" "$(run_setup fresh)"
check fresh-npm-rc "min-release-age=7" "$(cat "$work/fresh/npmrc")"
check fresh-pnpm-rc "minimum-release-age=10080" "$(cat "$work/fresh/pnpmrc")"
check fresh-npm-user-location "config set min-release-age=7 --location=user" \
  "$(grep '^config set' "$work/fresh/npm.log")"
check fresh-pnpm-global "config set -g minimum-release-age 10080" \
  "$(grep '^config set' "$work/fresh/pnpm.log")"

# -- the same host again: reads only, the files are left alone ----------------
check rerun-exit "0" "$(run_setup fresh)"
check rerun-npm-no-second-write "1" "$(writes fresh npm)"
check rerun-pnpm-no-second-write "1" "$(writes fresh pnpm)"
check rerun-npm-rc-unchanged "min-release-age=7" "$(cat "$work/fresh/npmrc")"
check rerun-pnpm-rc-unchanged "minimum-release-age=10080" "$(cat "$work/fresh/pnpmrc")"

# -- Node 22's bundled npm 10 predates the key: fail loudly, name the fix, and
#    still configure pnpm rather than abandon the run -------------------------
check old-npm-fails "1" "$(NPM_STUB_VERSION=10.9.2 run_setup old-npm)"
check old-npm-no-write "0" "$(writes old-npm npm)"
check_contains old-npm-names-fix "npm install -g npm" "$(cat "$work/old-npm/out")"
check old-npm-pnpm-still-set "minimum-release-age=10080" "$(cat "$work/old-npm/pnpmrc")"

# -- pnpm before 10.16 likewise --------------------------------------------------
check old-pnpm-fails "1" "$(PNPM_STUB_VERSION=10.15.0 run_setup old-pnpm)"
check old-pnpm-no-write "0" "$(writes old-pnpm pnpm)"
check_contains old-pnpm-names-fix "corepack use pnpm@latest" "$(cat "$work/old-pnpm/out")"
check old-pnpm-npm-still-set "min-release-age=7" "$(cat "$work/old-pnpm/npmrc")"

# -- a version floor is inclusive, and 11.9 < 11.10 as versions, not strings ---
check floor-inclusive "0" "$(NPM_STUB_VERSION=11.10.0 run_setup floor)"
check floor-numeric "1" "$(NPM_STUB_VERSION=11.9.5 run_setup below-floor)"

# -- no npm on PATH at all: a failure, not a skip --------------------------------
check no-npm-fails "1" "$(run_setup no-npm "$work/bin-no-npm")"
check_contains no-npm-message "npm not installed" "$(cat "$work/no-npm/out")"

# -- the symlinked files carry 7 days in each tool's own unit -------------------
count() { grep -cx -- "$2" "$module/$1"; }
check bun-seconds "1" "$(count bunfig.toml 'minimumReleaseAge = 604800')"
check uv-duration "1" "$(count uv.toml 'exclude-newer = "7 days"')"
check pip-iso-duration "1" "$(count pip.conf 'uploaded-prior-to = P7D')"
check pip-global-section "1" "$(count pip.conf '\[global\]')"
check cargo-duration "1" "$(count cargo-config.toml 'global-min-publish-age = "7 days"')"

# Every declared symlink source exists, on both conf files.
while read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  src=${line%% -> *}
  check "symlink-source-$src" "0" "$([ -f "$module/$src" ] && echo 0 || echo 1)"
done < <(cat "$module/symlinks.conf" "$module/symlinks.macos.conf")

# The two TOML files parse in the tools that read them, when those tools are
# here. uv rejects a bad duration at load time, cargo rejects malformed TOML.
if command -v uv >/dev/null 2>&1; then
  check uv-toml-loads "0" \
    "$(
      UV_CONFIG_FILE="$module/uv.toml" uv pip compile --offline --no-header -q - <<<'' >/dev/null 2>&1
      echo $?
    )"
else
  echo "SKIP uv-toml-loads: uv not installed"
fi
if command -v cargo >/dev/null 2>&1; then
  check cargo-toml-loads "0" "$(
    cargo --config "$module/cargo-config.toml" --list >/dev/null 2>&1
    echo $?
  )"
else
  echo "SKIP cargo-toml-loads: cargo not installed"
fi

if ((fails == 0)); then
  printf 'all passed\n'
  exit 0
fi
printf '%s failed\n' "$fails"
exit 1
