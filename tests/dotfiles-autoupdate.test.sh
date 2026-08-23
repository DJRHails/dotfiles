#!/usr/bin/env bash
# Behavior suite for modules/dotfiles-autoupdate/update.sh.
# Self-contained: `bash tests/dotfiles-autoupdate.test.sh`. Exits non-zero on failure.
#
# Covers the stash-and-reapply path, which exists because apps write into
# tracked config through their symlinks: a local edit must survive the daily
# fast-forward, and one that conflicts must be parked in a stash rather than
# popped into the working tree as conflict markers.
set -u

# The suite builds its own repos under /tmp. When it runs from a git hook —
# prek at commit time, especially from a linked worktree — git exports
# GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE pointing at the committing repo, which
# hijacks every nested git call here (21 checks fail with "GIT_WORK_TREE not
# allowed without specifying GIT_DIR"). Drop all inherited git env.
unset "${!GIT_@}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
update_sh="$repo_root/modules/dotfiles-autoupdate/update.sh"

# pwd -P: git canonicalizes paths (macOS /var -> /private/var), so the
# sandbox-escape guard's prefix match needs $work canonicalized the same way.
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

git_quiet() { git -C "$clone" -c user.email=t@t -c user.name=t "$@" > /dev/null 2>&1; }

# The script prepends $HOME/.local/bin to PATH, so a fake HOME is the only way
# to put a stub ahead of a real glassine — and it keeps the suite from writing
# ~/.gitconfig.github-ssh into the developer's actual home. git identity has to
# be supplied because the stash the updater takes creates commit objects.
fake_home="$work/home"

# A bare origin plus a clone, so the script's fetch/merge run for real.
setup_repo() {
  rm -rf -- "$work/origin" "$work/clone" "$work/state" "$fake_home" "$work/glassine.calls"
  mkdir -p "$fake_home"
  printf '[user]\n\tname = t\n\temail = t@t\n' > "$fake_home/.gitconfig"
  git init --quiet --bare "$work/origin"
  git clone --quiet "$work/origin" "$work/clone" 2> /dev/null
  clone="$work/clone"
  # Refuse to continue unless git actually resolves to the sandbox clone. The
  # 2026-08-11 incident: prek exports GIT_DIR for a commit made from a linked
  # worktree, which redirected every `git -C "$clone"` here at the real repo —
  # fixture commits landed on the real branch and `push origin HEAD:main`
  # fast-forwarded the real remote's main. The unset at the top fixes that
  # leak; this guard refuses any future one before a single commit is made.
  local resolved
  resolved="$(git -C "$clone" rev-parse --absolute-git-dir 2> /dev/null)"
  case "$resolved" in
    "$work"/*) ;;
    *)
      printf 'ABORT: git -C clone resolves to [%s], outside the sandbox %s — ambient git env leaked\n' \
        "${resolved:-nothing}" "$work" >&2
      exit 1
      ;;
  esac
  printf 'default\n' > "$clone/settings.json"
  printf 'untouched\n' > "$clone/other.txt"
  git_quiet add -A
  git_quiet commit -m "initial"
  git_quiet push -u origin HEAD:main
  git_quiet branch --set-upstream-to=origin/main
}

# Land a new upstream commit, made in a throwaway clone so $clone stays behind.
push_upstream() {
  local file=$1 content=$2 up="$work/upstream"
  rm -rf -- "$up"
  git clone --quiet "$work/origin" "$up" 2> /dev/null
  printf '%s\n' "$content" > "$up/$file"
  git -C "$up" -c user.email=t@t -c user.name=t add -A > /dev/null
  git -C "$up" -c user.email=t@t -c user.name=t commit -m "upstream edit" > /dev/null
  git -C "$up" push --quiet origin HEAD:main
}

# Runs in a subshell via `log="$(run_update)"`, so the exit status goes to a
# file rather than a variable the caller could never see.
run_update() {
  DOTFILES="$clone" XDG_STATE_HOME="$work/state" HOME="$fake_home" \
    bash "$update_sh" > /dev/null 2>&1
  printf '%s\n' "$?" > "$work/status"
  cat "$work/state/dotfiles/autoupdate.log"
}

# A stand-in for glassine on PATH, faithful to the two parts of its contract the
# updater leans on: `init` rewrites still-encrypted worktree files in place, and
# reports how many on stdout. Real decryption needs sops, an age identity and a
# .sops.yaml — none of which belong in a behaviour test of the updater.
stub_glassine() {
  local mode=${1:-repair}
  mkdir -p "$fake_home/.local/bin"
  cat > "$fake_home/.local/bin/glassine" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$work/glassine.calls"
if [ "$mode" = fail ]; then
  echo 'glassine: no decryption identity found' >&2
  exit 1
fi
count=0
while IFS= read -r f; do
  grep -qF 'ENC[AES256_GCM' "$clone/\$f" 2> /dev/null || continue
  printf 'decrypted-plaintext\n' > "$clone/\$f"
  count=\$((count + 1))
done < <(git -C "$clone" ls-files)
[ "\$count" -eq 0 ] ||
  printf 'glassine: decrypted %d file(s) into the working tree\n' "\$count"
exit 0
STUB
  chmod +x "$fake_home/.local/bin/glassine"
}

# Mark the clone as a glassine repo the way a real one is marked: a tracked
# .gitattributes rule. That, not the local config, is what the updater gates on.
enable_glassine_filter() {
  printf 'secret/** filter=glassine\n' > "$clone/.gitattributes"
  git_quiet add .gitattributes
  git_quiet commit -m "declare a glassine rule"
  # Push it: an unpushed commit would diverge the clone and suppress the pull
  # these cases still depend on.
  git_quiet push origin HEAD:main
}

# --- a local edit that does not collide is carried over the update ----------
setup_repo
push_upstream other.txt "upstream-changed"
printf 'locally-picked-model\n' > "$clone/settings.json"
log="$(run_update)"

check "clean reapply: pulls" \
  "upstream-changed" "$(cat "$clone/other.txt")"
check "clean reapply: keeps the local edit" \
  "locally-picked-model" "$(cat "$clone/settings.json")"
check "clean reapply: nothing left in the stash" \
  "0" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "clean reapply: logged" \
  "1" "$(grep -c 'reapplied local changes' <<< "$log")"

# --- a local edit to the same lines is parked, never popped as markers ------
setup_repo
push_upstream settings.json "upstream-model"
printf 'locally-picked-model\n' > "$clone/settings.json"
log="$(run_update)"

check "conflict: still pulls" \
  "upstream-model" "$(cat "$clone/settings.json")"
# Count with `grep -c` on one file, never `grep -rc`: BSD grep prefixes the
# filename in recursive mode, so the comparison broke on macOS while the
# behaviour under test was fine.
check "conflict: no conflict markers in the tree" \
  "0" "$(grep -c '^<<<<<<<' "$clone/settings.json" | tr -d ' ')"
check "conflict: tree is clean" \
  "" "$(git -C "$clone" status --porcelain)"
check "conflict: local work kept in the stash" \
  "1" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "conflict: stash is recoverable" \
  "locally-picked-model" "$(git -C "$clone" stash show -p stash@'{0}' | grep '^+locally' | cut -c2-)"
check "conflict: logged with the recovery command" \
  "1" "$(grep -c 'CONFLICT with the update' <<< "$log")"

# --- a clean tree still fast-forwards, and takes no stash -------------------
setup_repo
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "clean tree: pulls" \
  "upstream-changed" "$(cat "$clone/other.txt")"
check "clean tree: no stash taken" \
  "0" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "clean tree: logged as updated" \
  "1" "$(grep -c 'updated: ' <<< "$log")"

# --- already up to date is a no-op ------------------------------------------
log="$(run_update)"
check "up to date: logged" "1" "$(grep -c 'ok: up to date' <<< "$log")"

# --- a diverged branch is never auto-merged ---------------------------------
setup_repo
push_upstream other.txt "upstream-changed"
printf 'local commit\n' > "$clone/local.txt"
git_quiet add -A
git_quiet commit -m "local divergence"
local_head="$(git -C "$clone" rev-parse HEAD)"
log="$(run_update)"

check "diverged: HEAD untouched" "$local_head" "$(git -C "$clone" rev-parse HEAD)"
check "diverged: logged" "1" "$(grep -c 'diverged from upstream' <<< "$log")"

# --- ciphertext stranded in the worktree is detected and repaired -----------
# A hand-resolved conflict (or a checkout with glassine off PATH) writes the raw
# sops envelope into the working tree while git still calls the tree clean, so
# nothing flags it. Two skills sat unreadable that way for a week.
setup_repo
stub_glassine
enable_glassine_filter
printf 'ENC[AES256_GCM,data:xx]\n' > "$clone/secret.md"
git_quiet add -A
git_quiet commit -m "encrypted-at-rest file"
git_quiet push origin HEAD:main
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "glassine repair: worktree is plaintext again" \
  "decrypted-plaintext" "$(cat "$clone/secret.md")"
check "glassine repair: names the repair in the log" \
  "1" "$(grep -c 'repaired unsmudged files: decrypted 1 file' <<< "$log")"
check "glassine repair: went through init" \
  "init" "$(cat "$work/glassine.calls")"

# --- a repo that has not opted into glassine is never touched ---------------
# Running `glassine init` against an unmanaged repo would bootstrap .sops.yaml
# and filters into it, so the config gate has to hold.
setup_repo
stub_glassine
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "no glassine filter: glassine is not invoked" \
  "never-called" "$(cat "$work/glassine.calls" 2> /dev/null || echo never-called)"
check "no glassine filter: still pulls" \
  "upstream-changed" "$(cat "$clone/other.txt")"

# --- a glassine that cannot decrypt is logged, never fatal ------------------
# No identity on this host is a warning: the update itself must still land, and
# the rest of the daily run must still happen.
setup_repo
stub_glassine fail
enable_glassine_filter
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "glassine failure: warned" \
  "1" "$(grep -c 'WARNING: glassine init failed' <<< "$log")"
check "glassine failure: the update still landed" \
  "upstream-changed" "$(cat "$clone/other.txt")"
check "glassine failure: no repair claimed" \
  "0" "$(grep -c 'repaired unsmudged files' <<< "$log")"
# enable_glassine_filter sets no local config, so this case is also the
# compound failure: config missing AND init failed. init dies before writing
# any filter config, so the plaintext-staging window stays open — the log
# must name that, not just the ciphertext direction.
check "glassine failure: names the still-open plaintext window" \
  "1" "$(grep -c 'filter config is still missing' <<< "$log")"

# With the config intact, a failed init carries no plaintext risk — no scare.
setup_repo
stub_glassine fail
enable_glassine_filter
git -C "$clone" config filter.glassine.clean 'glassine clean %f'
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "intact config + failed init: no plaintext warning" \
  "0" "$(grep -c 'filter config is still missing' <<< "$log")"

# --- a lost filter config is restored, and said out loud --------------------
# filter.glassine.* lives in .git/config, so it is never cloned and easily lost.
# Meanwhile .gitattributes still declares the rule, so git runs no filter and
# stages managed files as plaintext. Gating on that config would skip this repo.
setup_repo
stub_glassine
enable_glassine_filter
git -C "$clone" config --unset filter.glassine.clean 2> /dev/null
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "lost config: repaired anyway, not skipped" \
  "init" "$(cat "$work/glassine.calls")"
check "lost config: warns that plaintext was staging" \
  "1" "$(grep -c 'restored the missing glassine filter config' <<< "$log")"

# A repo already holding the config is repaired without the scary line.
setup_repo
stub_glassine
enable_glassine_filter
git -C "$clone" config filter.glassine.clean 'glassine clean %f'
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "intact config: no spurious restore warning" \
  "0" "$(grep -c 'restored the missing glassine filter config' <<< "$log")"

# --- a clean-tree update still runs the steps after the pull ----------------
# `update_dotfiles` ends on the stash branch, so an `&&` one-liner there made it
# return 1 whenever no stash was taken; `set -e` then killed the run before the
# pi refresh and the ssh-rewrite. Two fast-forwards on 2026-08-05 skipped them
# silently, so assert on a side effect of the last step, not just the exit code.
setup_repo
mkdir -p "$fake_home/.ssh"
printf 'Host github.com\n  User git\n' > "$fake_home/.ssh/config"
push_upstream other.txt "upstream-changed"
log="$(run_update)"

check "clean-tree update: exits 0" "0" "$(cat "$work/status")"
check "clean-tree update: no stash was taken" \
  "0" "$(git -C "$clone" stash list | wc -l | tr -d ' ')"
check "clean-tree update: later steps still ran" \
  "1" "$([ -f "$fake_home/.gitconfig.github-ssh" ] && echo 1 || echo 0)"

# --- sfw refresh: stubs -------------------------------------------------------
# ensure_sfw_fresh talks to the network twice (release check, binary download),
# so both ride a curl stub; sfw itself is a stub that reports a fixed version.
# Everything lands in $fake_home/.local/bin, which update.sh prepends to PATH.
stub_sfw() {
  mkdir -p "$fake_home/.local/bin"
  printf '#!/usr/bin/env bash\necho "Socket Firewall Free, version %s"\n' "$1" \
    > "$fake_home/.local/bin/sfw"
  chmod +x "$fake_home/.local/bin/sfw"
}

stub_curl() {
  local mode=${1:-ok}
  mkdir -p "$fake_home/.local/bin"
  cat > "$fake_home/.local/bin/curl" << STUB
#!/usr/bin/env bash
[ "$mode" = offline ] && exit 6
out="" url=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out=\$2; shift ;;
    http*) url=\$1 ;;
  esac
  shift
done
case "\$url" in
  *api.github.com*) printf '{"tag_name": "v9.9.9"}\n' ;;
  *gantry.hails.info/health*) printf '{"version": "9.9.9"}\n' ;;
  *releases/download*)
    [ "$mode" = download-fail ] && exit 22
    if [ "$mode" = download-garbage ]; then
      printf '<html>captive portal</html>\n' > "\$out"
    else
      # A runnable fake: ensure_sfw_fresh execs the download before it may
      # replace the live binary; the embedded URL pins os/arch/tag assembly.
      printf '#!/usr/bin/env bash\n# downloaded-from %s\necho "Socket Firewall Free, version 9.9.9"\n' \
        "\$url" > "\$out"
    fi
    ;;
esac
exit 0
STUB
  chmod +x "$fake_home/.local/bin/curl"
}

# --- sfw refresh: a stale binary is replaced in place ------------------------
setup_repo
stub_sfw "1.0.0"
stub_curl ok
log="$(run_update)"

check "sfw stale: update logged" \
  "1" "$(grep -c 'sfw: updated 1.0.0 -> 9.9.9' <<< "$log")"
# Mirror the os/arch mapping so the check pins the URL template (repo path,
# ${os}-${arch} order, the v in the tag) on whatever host runs the suite.
exp_os="linux"
[ "$(uname -s)" = Darwin ] && exp_os="macos"
case "$(uname -m)" in aarch64 | arm64) exp_arch="arm64" ;; *) exp_arch="x86_64" ;; esac
check "sfw stale: binary replaced, download URL correct" \
  "# downloaded-from https://github.com/SocketDev/sfw-free/releases/download/v9.9.9/sfw-free-${exp_os}-${exp_arch}" \
  "$(sed -n 2p "$fake_home/.local/bin/sfw")"
check "sfw stale: replacement is executable" \
  "1" "$([ -x "$fake_home/.local/bin/sfw" ] && echo 1 || echo 0)"

# --- sfw refresh: a failed download leaves the old binary in place ------------
setup_repo
stub_sfw "1.0.0"
stub_curl download-fail
log="$(run_update)"

check "sfw download-fail: failure logged with curl exit" \
  "1" "$(grep -c 'sfw: FAILED to update to 9.9.9 (curl exit 22)' <<< "$log")"
check "sfw download-fail: old binary intact" \
  "1" "$(grep -c 'version 1.0.0' "$fake_home/.local/bin/sfw")"
check "sfw download-fail: old binary still executable" \
  "1" "$([ -x "$fake_home/.local/bin/sfw" ] && echo 1 || echo 0)"
check "sfw download-fail: exits 0" "0" "$(cat "$work/status")"

# --- sfw refresh: a garbage download is rejected, never installed --------------
setup_repo
stub_sfw "1.0.0"
stub_curl download-garbage
log="$(run_update)"

check "sfw garbage: rejection logged" \
  "1" "$(grep -c 'sfw: FAILED to update to 9.9.9 (downloaded file is not a working sfw)' <<< "$log")"
check "sfw garbage: old binary intact" \
  "1" "$(grep -c 'version 1.0.0' "$fake_home/.local/bin/sfw")"
check "sfw garbage: no temp file left beside the binary" \
  "0" "$(find "$fake_home/.local/bin" -name 'sfw.*' | wc -l | tr -d ' ')"

# --- sfw refresh: an unwritable bin dir skips the refresh, never the run ------
# The same-directory mktemp is the one refresh step that can fail outside the
# curl/verify guards; under set -e an unguarded failure would kill the whole
# update script, not just the refresh.
setup_repo
stub_sfw "1.0.0"
stub_curl ok
mkdir -p "$fake_home/.ssh"
printf 'Host github.com\n  User git\n' > "$fake_home/.ssh/config"
chmod 555 "$fake_home/.local/bin"
log="$(run_update)"
chmod 755 "$fake_home/.local/bin"

check "sfw unwritable dir: skip logged" \
  "1" "$(grep -c 'sfw: FAILED to create temp file beside .*sfw, not refreshing' <<< "$log")"
check "sfw unwritable dir: exits 0" "0" "$(cat "$work/status")"
check "sfw unwritable dir: old binary intact" \
  "1" "$(grep -c 'version 1.0.0' "$fake_home/.local/bin/sfw")"
check "sfw unwritable dir: later steps still ran" \
  "1" "$([ -f "$fake_home/.gitconfig.github-ssh" ] && echo 1 || echo 0)"

# --- sfw refresh: a current binary is left untouched --------------------------
setup_repo
stub_sfw "9.9.9"
stub_curl ok
log="$(run_update)"

check "sfw current: nothing logged" \
  "0" "$(grep -c 'sfw:' <<< "$log")"
check "sfw current: binary untouched" \
  "#!/usr/bin/env" "$(head -1 "$fake_home/.local/bin/sfw" | cut -d' ' -f1)"

# --- sfw refresh: an offline release check is logged and never fatal ----------
setup_repo
stub_sfw "1.0.0"
stub_curl offline
mkdir -p "$fake_home/.ssh"
printf 'Host github.com\n  User git\n' > "$fake_home/.ssh/config"
log="$(run_update)"

check "sfw offline: skip logged" \
  "1" "$(grep -c 'sfw: release check failed (offline?)' <<< "$log")"
check "sfw offline: exits 0" "0" "$(cat "$work/status")"
check "sfw offline: later steps still ran" \
  "1" "$([ -f "$fake_home/.gitconfig.github-ssh" ] && echo 1 || echo 0)"

# --- gantry refresh: the ssh rewrite is in place before the private clone ----
# ensure_gantry_cli_fresh clones the private gantry repo over https and rides
# ensure_github_ssh_rewrite's insteadOf on keyed hosts, so the rewrite step
# must run first (PR #131's post-merge finding: the old order hit an
# unauthenticated clone on hosts whose rewrite file was missing and converged
# a day late). The uv stub records whether the rewrite file existed at install
# time, so a future shuffle of the call list fails here instead of in prod.
stub_uv() {
  mkdir -p "$fake_home/.local/bin"
  cat > "$fake_home/.local/bin/uv" << STUB
#!/usr/bin/env bash
case "\$1 \${2:-}" in
  "tool list") echo "gantry v$1" ;;
  "tool install")
    if [ -f "$fake_home/.gitconfig.github-ssh" ]; then
      echo present > "$work/uv.rewrite-state"
    else
      echo missing > "$work/uv.rewrite-state"
    fi
    ;;
esac
exit 0
STUB
  chmod +x "$fake_home/.local/bin/uv"
}

setup_repo
stub_curl ok
stub_uv "1.0.0"
mkdir -p "$fake_home/.ssh"
printf 'Host github.com\n  User git\n' > "$fake_home/.ssh/config"
log="$(run_update)"

check "gantry stale: update logged" \
  "1" "$(grep -c 'gantry: updated 1.0.0 -> ' <<< "$log")"
check "gantry stale: ssh rewrite existed when the clone ran" \
  "present" "$(cat "$work/uv.rewrite-state" 2> /dev/null || echo never-invoked)"

if ((fails)); then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
