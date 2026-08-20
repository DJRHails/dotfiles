#!/usr/bin/env bash
# Reconcile taffy's self-hosted GitHub Actions runner pools against runners.conf.
#
# Run ON taffy — needs local `gh` auth (to mint registration tokens) and
# passwordless sudo (to create the service user and systemd units).
#
#     ./provision.sh                          # reconcile every repo in runners.conf
#     ./provision.sh DJRHails/gauntlet        # just this repo, count from the conf
#     ./provision.sh DJRHails/gauntlet 6      # just this repo, override the count
#
# Idempotent and convergent. A runner is (re)installed when its systemd unit is
# missing, dead, or pointing at the wrong directory; runners with an index above
# the configured count are stopped and deregistered, so lowering a number in
# runners.conf is how you shrink a pool.
#
# Each runner runs as the non-root `actions` user, in the `docker` group so it
# drives taffy's shared host daemon (the same one the gantry fleet uses), from
# /home/actions/<repo>-runner-<i>, under
# actions.runner.<owner>-<repo>.taffy-<i>.service (enabled => reboot-durable).
set -euo pipefail

RUNNER_VERSION="2.335.1" # bootstrap only — the runner self-updates on first connect
LABELS="self-hosted,linux,x64,taffy"
RUNNER_USER="actions"
RUNNER_HOME="/home/${RUNNER_USER}"
CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runners.conf"

die() {
  echo "error: $*" >&2
  exit 1
}

runner_dir() {
  local repo="$1" idx="$2"
  echo "${RUNNER_HOME}/${repo#*/}-runner-${idx}"
}

runner_svc() {
  local repo="$1" idx="$2"
  echo "actions.runner.${repo%%/*}-${repo#*/}.taffy-${idx}.service"
}

# Per-runner tool and cache homes, written to <dir>/.env (the runner sources it
# for every job).
#
# Without this every runner on the host shares one $HOME, so the toolchain
# caches collide: pnpm/action-setup puts its content-addressed store under
# PNPM_HOME (/home/actions/setup-pnpm/...), and two repos installing at the same
# moment race on the same files — observed as
# `ERR_PNPM_ENOENT ... copyfile '/home/actions/setup-pnpm/.../store/v10/...'`.
# corepack, rustup/cargo, uv, npm and go all have the same shape. A hosted
# runner never hits this because its $HOME is a fresh VM.
#
# Scoped to <dir>/_work/ rather than $RUNNER_TEMP so the cache still survives
# between jobs (a runner only ever runs one job at a time, so per-runner is
# collision-free without giving up reuse).
#
# HOME itself is repointed because the per-tool variables are not enough:
# pnpm/action-setup installs to `<os.homedir()>/setup-pnpm` from its own `dest`
# default, which ignores PNPM_HOME entirely, so two runners still collided with
# `ENOTEMPTY: directory not empty, rmdir '/home/actions/setup-pnpm'`. Giving each
# runner its own HOME closes the whole class rather than chasing one tool at a
# time. .gitconfig is seeded into it so git identity survives the move.
runner_env_content() {
  local dir="$1"
  cat <<ENV
HOME=${dir}/_home
XDG_CACHE_HOME=${dir}/_work/_cache
PNPM_HOME=${dir}/_work/_tool/pnpm
COREPACK_HOME=${dir}/_work/_tool/corepack
CARGO_HOME=${dir}/_work/_tool/cargo
RUSTUP_HOME=${dir}/_work/_tool/rustup
GOPATH=${dir}/_work/_tool/go
GOCACHE=${dir}/_work/_cache/go-build
UV_CACHE_DIR=${dir}/_work/_cache/uv
PIP_CACHE_DIR=${dir}/_work/_cache/pip
npm_config_cache=${dir}/_work/_cache/npm
ENV
}

# Converge <dir>/.env for every configured runner, restarting only those whose
# content actually changed (the runner reads .env at service start).
write_runner_envs() {
  local repo="$1" n="$2" i dir svc want
  for i in $(seq 1 "$n"); do
    dir="$(runner_dir "$repo" "$i")"
    [ -d "$dir" ] || continue
    want="$(runner_env_content "$dir")"
    if [ "$(sudo cat "${dir}/.env" 2>/dev/null || true)" = "$want" ]; then
      continue
    fi
    echo "  ${repo#*/} runner-${i}: refreshing .env (per-runner caches)"
    printf '%s\n' "$want" | sudo -u "$RUNNER_USER" tee "${dir}/.env" >/dev/null
    sudo -u "$RUNNER_USER" mkdir -p \
      "${dir}/_work/_cache" "${dir}/_work/_tool" "${dir}/_home"
    # Seed git identity into the new HOME, once — rustup/cargo and friends will
    # populate the rest themselves.
    if [ -f "${RUNNER_HOME}/.gitconfig" ] && [ ! -f "${dir}/_home/.gitconfig" ]; then
      sudo -u "$RUNNER_USER" cp "${RUNNER_HOME}/.gitconfig" "${dir}/_home/.gitconfig"
    fi
    # The restart aborts an in-flight job (accepted — .env changes are rare); a
    # failed restart must be loud, or the content check above hides it forever.
    svc="$(runner_svc "$repo" "$i")"
    sudo systemctl restart "$svc" ||
      echo "  warn: ${svc} restart failed — new .env not applied" >&2
  done
}

# A runner is healthy only if its unit is active AND anchored at the path we
# expect — a unit left at an old directory is silently the wrong runner.
runner_is_healthy() {
  local svc="$1" want="$2" have
  systemctl is-active --quiet "$svc" 2>/dev/null || return 1
  have="$(systemctl show -p WorkingDirectory --value "$svc" 2>/dev/null)"
  [ "$have" = "$want" ]
}

# Indices in 1..N whose runner needs creating or re-anchoring.
missing_indices() {
  local repo="$1" n="$2" i
  for i in $(seq 1 "$n"); do
    runner_is_healthy "$(runner_svc "$repo" "$i")" "$(runner_dir "$repo" "$i")" || echo "$i"
  done
}

install_runners() {
  local repo="$1" indices="$2" tokfile rmtokfile
  [ -n "$indices" ] || return 0

  # EXIT (not RETURN) so the token files are cleaned up even when set -e aborts
  # mid-function — RETURN traps don't fire on abort, and they outlive the
  # function and re-fire on every later return.
  tokfile="$(mktemp)"
  rmtokfile="$(mktemp)"
  chmod 600 "$tokfile" "$rmtokfile"
  # shellcheck disable=SC2064  # expand the paths now, not at trap time
  trap "rm -f '$tokfile' '$rmtokfile'" EXIT
  local _
  for _ in $indices; do
    gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token >>"$tokfile"
  done
  # Tearing down a previously-configured runner needs a REMOVE token —
  # `config.sh remove` rejects a registration token.
  gh api -X POST "repos/${repo}/actions/runners/remove-token" --jq .token >"$rmtokfile"

  # `sudo env` (not bare `sudo VAR=…`) so the assignments don't depend on a
  # SETENV-shaped sudoers rule.
  sudo env REPO="$repo" INDICES="$indices" VER="$RUNNER_VERSION" LABELS="$LABELS" \
    RU="$RUNNER_USER" HD="$RUNNER_HOME" TOKFILE="$tokfile" RMTOKFILE="$rmtokfile" bash <<'REMOTE'
set -euo pipefail
mapfile -t TOKENS <"$TOKFILE"
RMTOK="$(cat "$RMTOKFILE")"
SHORT="${REPO#*/}"

id -u "$RU" >/dev/null 2>&1 || useradd -m -s /bin/bash "$RU"
usermod -aG docker "$RU"
# Explicit mode: `install -d` on an existing directory resets it to 0755,
# silently making every runner $HOME world-traversable on a shared host.
install -d -m 0750 -o "$RU" -g "$RU" "$HD"

# Download the runner tarball once; every runner dir extracts from this cache.
CACHE="${HD}/.runner-cache"
runuser -u "$RU" -- mkdir -p "$CACHE"
if [ ! -f "${CACHE}/runner-${VER}.tgz" ]; then
  echo "  caching actions-runner v${VER}"
  # Download to a temp name — a partial file left by a dead curl would satisfy
  # the -f guard forever and wedge every later install at the tar step.
  runuser -u "$RU" -- curl -fsSL -o "${CACHE}/runner-${VER}.tgz.tmp" \
    "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-x64-${VER}.tar.gz"
  runuser -u "$RU" -- mv "${CACHE}/runner-${VER}.tgz.tmp" "${CACHE}/runner-${VER}.tgz"
fi

k=0
for i in $INDICES; do
  DIR="${HD}/${SHORT}-runner-${i}"
  TOK="${TOKENS[$k]}"
  k=$((k + 1))
  echo "  ${SHORT} runner-${i}: installing at ${DIR}"

  # Tear down whatever was there (a dead unit, or one anchored elsewhere).
  OLD="actions.runner.${REPO%%/*}-${SHORT}.taffy-${i}.service"
  if systemctl list-unit-files "$OLD" >/dev/null 2>&1 && systemctl cat "$OLD" >/dev/null 2>&1; then
    PREV="$(systemctl show -p WorkingDirectory --value "$OLD" 2>/dev/null || true)"
    systemctl stop "$OLD" 2>/dev/null || true
    if [ -n "$PREV" ] && [ -x "${PREV}/svc.sh" ]; then
      (cd "$PREV" && ./svc.sh uninstall) || true
      # Tokens travel via env + positional args, not spliced into script text —
      # that keeps them off the intermediate bash cmdline and closes the quoting
      # hole. config.sh's own argv still shows the token while it runs; that is
      # upstream's interface, and the tokens are single-purpose and expire in 1h.
      runuser -u "$RU" -- env RMTOK="$RMTOK" bash -c \
        'cd "$1" && ./config.sh remove --token "$RMTOK"' _ "$PREV" ||
        echo "  warn: could not deregister old ${SHORT} runner-${i}; wiping local state" >&2
    else
      # The directory (and its svc.sh) is gone but the unit survives — remove
      # it by hand or ./svc.sh install below refuses with "error: exists <unit>".
      systemctl disable "$OLD" 2>/dev/null || true
      rm -f "/etc/systemd/system/${OLD}"
      systemctl daemon-reload
    fi
    # Clear out a deregistered old install left at a different anchor.
    case "$PREV" in
    "$HD"/?*) if [ "$PREV" != "$DIR" ] && [ -d "$PREV" ]; then rm -rf -- "$PREV"; fi ;;
    esac
  fi

  # Start from a clean slate: stale .runner/.credentials from a failed remove
  # would make config.sh refuse with "already configured" (--replace only
  # resolves the server-side name collision, not the local guard).
  rm -rf -- "${DIR:?}"
  runuser -u "$RU" -- bash -c 'mkdir -p "$1" && cd "$1" && tar xzf "$2"' _ \
    "$DIR" "${CACHE}/runner-${VER}.tgz"
  runuser -u "$RU" -- env RTOK="$TOK" bash -c \
    'cd "$1" && ./config.sh --url "$2" --token "$RTOK" \
      --name "$3" --labels "$4" --unattended --replace' _ \
    "$DIR" "https://github.com/${REPO}" "taffy-${i}" "$LABELS"
  (cd "$DIR" && ./svc.sh install "$RU" && ./svc.sh start)
done
REMOTE

  rm -f "$tokfile" "$rmtokfile"
  trap - EXIT
}

# Deregister every taffy-<i> above the configured count, locally and on GitHub.
# Driven by GitHub's runner list — a local unit GitHub no longer knows about is
# not swept here.
prune_runners() {
  local repo="$1" n="$2" listing name idx id svc dir have
  # Capture first so a failed listing dies loudly — a failing process
  # substitution is invisible under set -e and would skip pruning silently.
  listing="$(gh api --paginate "repos/${repo}/actions/runners" \
    --jq '.runners[] | select(.name|startswith("taffy-")) | "\(.name) \(.id)"')" ||
    die "could not list ${repo} runners — refusing to prune blind"
  while read -r name id; do
    [ -n "$name" ] || continue
    idx="${name#taffy-}"
    case "$idx" in '' | *[!0-9]*) continue ;; esac
    # Inverted so a test *error* selects skip, never prune.
    [ "$idx" -gt "$n" ] || continue

    echo "  ${repo#*/} ${name}: pruning (pool is ${n})"
    svc="$(runner_svc "$repo" "$idx")"
    dir="$(runner_dir "$repo" "$idx")"
    if systemctl cat "$svc" >/dev/null 2>&1; then
      # `systemctl show` prints "" with exit 0 when the property is unset, and
      # a hand-edited unit could anchor anywhere — only trust paths under ours.
      have="$(systemctl show -p WorkingDirectory --value "$svc" 2>/dev/null || true)"
      case "$have" in "${RUNNER_HOME}"/?*) dir="$have" ;; esac
      sudo systemctl stop "$svc" 2>/dev/null || true
      if [ -x "${dir}/svc.sh" ]; then
        (cd "$dir" && sudo ./svc.sh uninstall) || true
      fi
    fi
    # Deregister first, delete local state only on success — a swallowed
    # failure here (e.g. 422 on a busy runner) would orphan the registration
    # while destroying the credentials it needs to ever deregister itself.
    if ! gh api -X DELETE "repos/${repo}/actions/runners/${id}" >/dev/null; then
      echo "  warn: GitHub deregistration failed for ${name} (id ${id}) — keeping ${dir} for retry" >&2
      continue
    fi
    case "$dir" in
    "${RUNNER_HOME}"/?*) if [ -d "$dir" ]; then sudo rm -rf -- "$dir"; fi ;;
    *) echo "  warn: refusing to remove '${dir}' — outside ${RUNNER_HOME}" >&2 ;;
    esac
  done <<<"$listing"
  return 0
}

reconcile() {
  local repo="$1" n="$2" indices
  # Validate before acting: an empty or non-numeric count (a conf line missing
  # its count, an argv typo, a duplicate conf entry via the awk lookup) would
  # otherwise error out of prune's integer test and deregister the whole pool.
  case "$repo" in
  */*/* | /* | */ | *[!A-Za-z0-9._/-]*) die "bad repo '${repo}' — expected <owner>/<repo>" ;;
  */*) ;;
  *) die "bad repo '${repo}' — expected <owner>/<repo>" ;;
  esac
  case "$n" in
  '' | *[!0-9]*) die "bad count '${n}' for ${repo} — expected an integer (0 drains the pool)" ;;
  esac
  echo ">> ${repo} (pool ${n})"
  indices="$(missing_indices "$repo" "$n" | tr '\n' ' ')"
  if [ -n "${indices// /}" ]; then
    install_runners "$repo" "$indices"
  else
    echo "  all ${n} runner(s) healthy"
  fi
  write_runner_envs "$repo" "$n"
  prune_runners "$repo" "$n"
}

main() {
  command -v gh >/dev/null || die "gh not found — run this on taffy with gh authed"
  [ -f "$CONF" ] || die "missing $CONF"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated"

  if [ $# -gt 0 ]; then
    local repo="$1" n="${2:-}"
    if [ -z "$n" ]; then
      n="$(awk -v r="$repo" '$1==r{print $2}' "$CONF")"
      [ -n "$n" ] || die "$repo not in runners.conf — pass a count explicitly"
    fi
    reconcile "$repo" "$n"
    return
  fi

  # `|| [ -n "$repo" ]` keeps a final line without a trailing newline — read
  # populates the vars but returns non-zero, which would silently drop it.
  local repo n _
  while read -r repo n _ || [ -n "$repo" ]; do
    case "$repo" in '' | '#'*) continue ;; esac
    reconcile "$repo" "$n"
  done < <(sed 's/#.*//' "$CONF")
}

main "$@"
