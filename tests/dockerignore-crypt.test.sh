#!/usr/bin/env bash
# Behavior suite for scripts/check-dockerignore-crypt.sh.
# Self-contained: `bash tests/dockerignore-crypt.test.sh`. Exits non-zero on failure.
#
# The check guards against plaintext leaking into a docker image layer, and its
# quiet failure is passing on everything: a pipeline that stops seeing encrypted
# files exits 0 on every commit. Each case runs the script in a scratch repo
# with one glassine directory rule and one single-file rule, so the "missing"
# cases fail only if the script really found the encrypted files.
set -u

unset "${!GIT_@}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="$(cd "$script_dir/.." && pwd)/scripts/check-dockerignore-crypt.sh"

work="$(cd "$(mktemp -d)" && pwd -P)"
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

# The machine's git config is shut out so the undefined glassine filter is a
# no-op on `git add`; the ceiling stops discovery from finding this checkout.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="${work%/*}"
repo="$work/repo"
mkdir -p "$repo/secret/sub" "$repo/conf" "$repo/plain"
git -C "$repo" init -q
printf '%s\n' 'secret/** filter=glassine' 'conf/key.toml filter=glassine' >"$repo/.gitattributes"
for f in secret/a.md secret/sub/b.md conf/key.toml conf/other.toml plain/c.md; do
  printf 'x\n' >"$repo/$f"
done
git -C "$repo" add -A

run_check() { # <.dockerignore lines...> -> exit code, then each reported missing file
  printf '%s\n' "$@" >"$repo/.dockerignore"
  local out rc
  out="$(cd "$repo/plain" && bash "$check_script" 2>&1)"
  rc=$?
  printf 'rc=%s' "$rc"
  printf '%s\n' "$out" | sed -n 's/^  - / /p' | tr -d '\n'
}

check "directory and file entries exclude every encrypted file" "rc=0" \
  "$(run_check '# comment' '' secret conf/key.toml)"
check "a missing directory entry names each file under it" "rc=1 secret/a.md secret/sub/b.md" \
  "$(run_check conf/key.toml)"
check "a missing file entry names that file" "rc=1 conf/key.toml" "$(run_check secret)"
check "a parent directory entry covers its encrypted descendants" "rc=0" "$(run_check secret conf)"
check "leading / and ./ and trailing / spellings are accepted" "rc=0" \
  "$(run_check /secret/ ./conf/key.toml)"
check "glob entries are not evaluated, so they fail closed" "rc=1 secret/a.md secret/sub/b.md" \
  "$(run_check 'sec*' conf/key.toml)"
check "a ! re-include line fails even when everything is excluded" "rc=1" \
  "$(run_check secret conf/key.toml '!plain')"
check "an indented ! re-include line fails too" "rc=1" \
  "$(run_check secret conf/key.toml '  !plain')"

rm "$repo/.dockerignore"
(cd "$repo" && bash "$check_script" >/dev/null 2>&1)
check "a missing .dockerignore fails" "rc=1" "rc=$?"

if ((fails)); then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
