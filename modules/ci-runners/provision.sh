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

runner_dir() { echo "${RUNNER_HOME}/${1#*/}-runner-${2}"; }
runner_svc() { echo "actions.runner.${1%%/*}-${1#*/}.taffy-${2}.service"; }

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
runner_env_content() {
  local dir="$1"
  cat <<ENV
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
    svc="$(runner_svc "$repo" "$i")"
    [ -d "$dir" ] || continue
    want="$(runner_env_content "$dir")"
    if [ "$(sudo cat "${dir}/.env" 2>/dev/null || true)" = "$want" ]; then
      continue
    fi
    echo "  ${repo#*/} runner-${i}: refreshing .env (per-runner caches)"
    printf '%s\n' "$want" | sudo -u "$RUNNER_USER" tee "${dir}/.env" >/dev/null
    sudo -u "$RUNNER_USER" mkdir -p \
      "${dir}/_work/_cache" "${dir}/_work/_tool"
    sudo systemctl restart "$svc" 2>/dev/null || true
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
  local repo="$1" indices="$2" tokfile
  [ -n "$indices" ] || return 0

  tokfile="$(mktemp)"
  chmod 600 "$tokfile"
  # shellcheck disable=SC2064  # expand $tokfile now, not at trap time
  trap "rm -f '$tokfile'" RETURN
  local _
  for _ in $indices; do
    gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token >>"$tokfile"
  done

  sudo REPO="$repo" INDICES="$indices" VER="$RUNNER_VERSION" LABELS="$LABELS" \
    RU="$RUNNER_USER" HD="$RUNNER_HOME" TOKFILE="$tokfile" bash <<'REMOTE'
set -euo pipefail
mapfile -t TOKENS <"$TOKFILE"
SHORT="${REPO#*/}"

id -u "$RU" >/dev/null 2>&1 || useradd -m -s /bin/bash "$RU"
usermod -aG docker "$RU"
install -d -o "$RU" -g "$RU" "$HD"

# Download the runner tarball once; every runner dir extracts from this cache.
CACHE="${HD}/.runner-cache"
runuser -u "$RU" -- mkdir -p "$CACHE"
if [ ! -f "${CACHE}/runner-${VER}.tgz" ]; then
  echo "  caching actions-runner v${VER}"
  runuser -u "$RU" -- curl -fsSL -o "${CACHE}/runner-${VER}.tgz" \
    "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-x64-${VER}.tar.gz"
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
      runuser -u "$RU" -- bash -c "cd '$PREV' && ./config.sh remove --token '${TOK}'" || true
    fi
  fi

  runuser -u "$RU" -- bash -c "mkdir -p '${DIR}' && cd '${DIR}' && tar xzf '${CACHE}/runner-${VER}.tgz'"
  runuser -u "$RU" -- bash -c "cd '${DIR}' && ./config.sh \
    --url 'https://github.com/${REPO}' --token '${TOK}' \
    --name 'taffy-${i}' --labels '${LABELS}' --unattended --replace"
  (cd "$DIR" && ./svc.sh install "$RU" && ./svc.sh start)
done
REMOTE
}

# Deregister every taffy-<i> above the configured count, locally and on GitHub.
prune_runners() {
  local repo="$1" n="$2" name idx id
  while read -r name id; do
    [ -n "$name" ] || continue
    idx="${name#taffy-}"
    case "$idx" in '' | *[!0-9]*) continue ;; esac
    [ "$idx" -le "$n" ] && continue

    echo "  ${repo#*/} ${name}: pruning (pool is ${n})"
    local svc dir
    svc="$(runner_svc "$repo" "$idx")"
    dir="$(runner_dir "$repo" "$idx")"
    if systemctl cat "$svc" >/dev/null 2>&1; then
      dir="$(systemctl show -p WorkingDirectory --value "$svc" 2>/dev/null || echo "$dir")"
      sudo systemctl stop "$svc" 2>/dev/null || true
      [ -x "${dir}/svc.sh" ] && (cd "$dir" && sudo ./svc.sh uninstall) || true
    fi
    gh api -X DELETE "repos/${repo}/actions/runners/${id}" 2>/dev/null || true
    [ -d "$dir" ] && sudo rm -rf -- "$dir"
  done < <(gh api "repos/${repo}/actions/runners" --jq '.runners[] | select(.name|startswith("taffy-")) | "\(.name) \(.id)"' 2>/dev/null)
}

reconcile() {
  local repo="$1" n="$2" indices
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

  while read -r repo n _; do
    case "$repo" in '' | '#'*) continue ;; esac
    reconcile "$repo" "$n"
  done < <(sed 's/#.*//' "$CONF")
}

main "$@"
