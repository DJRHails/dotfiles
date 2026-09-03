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
# Idempotent and convergent. Every managed unit gets the self-heal restart
# drop-in (re)written first; a unit sitting in `failed` with its registration
# intact is then reset and started, not rebuilt. A runner is (re)installed only
# when its unit is missing, unregistered, or anchored at the wrong directory;
# runners with an index above the configured count are stopped and
# deregistered, so lowering a number in runners.conf is how you shrink a pool.
# Every runner's own $HOME gitconfig is also pointed at the github.com
# credential helper (install_git_helper below), so a fetch GitHub's anonymous
# throttle challenges retries with the host's public-read-only token.
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
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${MODULE_DIR}/runners.conf"
GIT_HELPER_SRC="${MODULE_DIR}/git-credential-public-read"
GIT_HELPER="/usr/local/lib/actions-runner/git-credential-public-read"
GITHUB_TOKEN_DIR="/etc/actions-runner"

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

# The systemd drop-in every managed unit carries.
#
# svc.sh generates a unit with NO Restart= directive, so systemd's default
# (Restart=no) applies and the FIRST oom-kill latches the runner into `failed`
# for good. taffy overcommits memory by design and the runner processes carry
# oom_score_adj=500, so the kernel sacrifices them first — expected load, not a
# crash. gantry's provisioner has carried this drop-in since the 2026-08-05
# window took out both gantry runners and touchstone taffy-3; the pools built
# here never had it, and on 2026-08-31/09-01 touchstone taffy-1, -3 and -4 died
# idle between jobs and stayed offline until someone could reach the host,
# leaving 29 CI runs queued behind the one survivor.
#
# StartLimit* keeps a genuine crash-loop (deregistered runner, broken install)
# from spinning forever: five starts inside five minutes latches the unit, and
# ensure_restart_policy clears that latch on the next reconcile.
restart_dropin_content() {
  cat <<'UNIT'
# Managed by modules/ci-runners/provision.sh — see restart_dropin_content there.
# Self-heal after an oom-kill, rate-limited so a genuine crash-loop still gives
# up rather than spinning forever.
[Unit]
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Restart=always
RestartSec=20
# systemd's default OOMPolicy=stop stops the WHOLE unit when the kernel kills
# any process in its cgroup — and on a runner that process is almost always a
# job step (a test worker, a headless chromium), not the listener. Every such
# kill therefore cancelled the running job, bounced the listener, and spent one
# of the five starts above; five inside five minutes latches the pool offline
# with every registration intact (touchstone taffy-2 reached "restart counter
# is at 6" on 2026-09-02). With `continue` the killed step fails on its own and
# the listener reports it; Restart= is left for the listener itself dying.
OOMPolicy=continue
# svc.sh's unit template sets KillMode=process, so on a stop — or on the unit
# failing because runsvc.sh itself died — systemd signals only that wrapper and
# leaves the Runner.Listener/Runner.Worker tree it spawned alive in the cgroup.
# The next start (Restart= above, or ensure_restart_policy's revive) then runs a
# second listener beside the survivor, and every job that runner takes is set up
# twice in one directory and dies in seconds with `_diag/pages/<run>_<job>_1.log
# already exists` (touchstone taffy-4 and taffy-2 on 2026-09-02, one minute after
# the revive). `mixed` keeps the graceful path (SIGTERM to runsvc.sh only) and
# SIGKILLs whatever is still in the cgroup once the stop timeout expires or the
# unit dies.
KillMode=mixed
UNIT
}

# (Re)write the drop-in onto every configured unit that exists, and revive any
# unit sitting in `failed` whose registration is still intact.
#
# Runs BEFORE the health check so a runner systemd could have restarted itself
# is repaired in place rather than torn down and re-registered — a rebuild
# wipes <dir>/_diag, which is the only record of why the runner died. Written
# unconditionally on content change, never only at install: an already-running
# runner is exactly the one still missing the policy.
#
# "Registration intact" needs BOTH halves: the `.runner` file on disk AND the
# name still in GitHub's runner list. `start` returns 0 the moment a Type=simple
# unit forks, so reviving a runner that dies right after reports success, reads
# as `active` to the health check below, and latches it out of the reinstall —
# and the local file alone cannot tell the two cases apart. config.sh writes
# `.runner`; nothing server-side ever removes it, so it survives GitHub dropping
# the registration (the 14-day offline auto-removal, a delete from the repo's
# runners page). An oom-killed runner stays listed (offline) and is revived; a
# deregistered one is skipped here and falls through to the reinstall. The list
# is fetched once per repo, and only once a `failed` unit still holding its
# `.runner` is actually seen.
ensure_restart_policy() {
  local repo="$1" n="$2" i svc dir dropin want state registered listed=0
  want="$(restart_dropin_content)"
  for i in $(seq 1 "$n"); do
    svc="$(runner_svc "$repo" "$i")"
    dir="$(runner_dir "$repo" "$i")"
    systemctl cat "$svc" >/dev/null 2>&1 || continue
    dropin="/etc/systemd/system/${svc}.d/restart.conf"
    if [ "$(sudo cat "$dropin" 2>/dev/null || true)" != "$want" ]; then
      echo "  ${repo#*/} runner-${i}: writing restart drop-in"
      sudo install -d -m 0755 "$(dirname "$dropin")"
      printf '%s\n' "$want" | sudo tee "$dropin" >/dev/null
      sudo systemctl daemon-reload
    fi
    state="$(systemctl show -p ActiveState --value "$svc" 2>/dev/null || true)"
    [ "$state" = "failed" ] || continue
    # Local probe first: a missing `.runner` settles the case without paying a
    # GitHub round trip — or dying on one — for a unit that is skipped anyway.
    if ! sudo test -f "${dir}/.runner"; then
      echo "  ${repo#*/} runner-${i}: failed with no .runner on disk — will be reinstalled"
      continue
    fi
    if [ "$listed" = 0 ]; then
      # Captured, not piped: a failed listing must die loudly, or every failed
      # unit would silently read as deregistered and be rebuilt.
      registered="$(gh api --paginate "repos/${repo}/actions/runners" --jq '.runners[].name')" ||
        die "could not list ${repo} runners — refusing to revive blind"
      listed=1
    fi
    if ! grep -qx -- "taffy-${i}" <<<"$registered"; then
      echo "  ${repo#*/} runner-${i}: failed and no longer registered — will be reinstalled"
      continue
    fi
    echo "  ${repo#*/} runner-${i}: clearing failed state and restarting"
    sudo systemctl reset-failed "$svc"
    sudo systemctl start "$svc" ||
      echo "  warn: ${svc} start failed — will be reinstalled" >&2
  done
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
#
# DOCKER_CONFIG is in the same list for the same reason, and it is the one with
# teeth: buildx stores its *current builder* pointer under $DOCKER_CONFIG, and
# `docker/setup-buildx-action` does a global `--use`. With it shared, one repo's
# build repoints "current" mid-flight and another repo's post-step then removes
# that builder underneath a running build — observed on words.hails.info as a
# buildkit `graceful_stop` GOAWAY caused by api.hails.info's teardown. It also
# stops `docker/login-action` writing GHCR credentials into a home directory
# shared by every repo on the host.
runner_env_content() {
  local dir="$1"
  cat <<ENV
HOME=${dir}/_home
DOCKER_CONFIG=${dir}/_work/_docker
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
#
# EVERY filesystem probe below is privileged. /home/actions is owned by the
# `actions` user at mode 0750 and this script runs as an ordinary user, so a bare
# `[ -d "$dir" ]` is FALSE for a directory that plainly exists. That is not
# hypothetical: on 2026-08-21 the mode tightened, every test silently failed, the
# loop `continue`d past all 47 runners, and eight freshly-built runners were left
# with no per-runner env at all — no HOME, no DOCKER_CONFIG — which is what let
# the cross-repo buildx race happen. It printed nothing and exited 0.
write_runner_envs() {
  local repo="$1" n="$2" i dir svc want
  for i in $(seq 1 "$n"); do
    dir="$(runner_dir "$repo" "$i")"
    if ! sudo test -d "$dir"; then
      # A configured index with no directory means install did not happen. Say so
      # — skipping quietly is how this went unnoticed for a whole fleet.
      echo "  warn: ${repo#*/} runner-${i}: ${dir} missing — no .env written" >&2
      continue
    fi
    want="$(runner_env_content "$dir")"
    if [ "$(sudo cat "${dir}/.env" 2>/dev/null || true)" = "$want" ]; then
      continue
    fi
    echo "  ${repo#*/} runner-${i}: refreshing .env (per-runner caches)"
    printf '%s\n' "$want" | sudo -u "$RUNNER_USER" tee "${dir}/.env" >/dev/null
    sudo -u "$RUNNER_USER" mkdir -p \
      "${dir}/_work/_cache" "${dir}/_work/_tool" "${dir}/_work/_docker" "${dir}/_home"
    # Seed git identity into the new HOME, once — rustup/cargo and friends will
    # populate the rest themselves.
    if sudo test -f "${RUNNER_HOME}/.gitconfig" && ! sudo test -f "${dir}/_home/.gitconfig"; then
      sudo -u "$RUNNER_USER" cp "${RUNNER_HOME}/.gitconfig" "${dir}/_home/.gitconfig"
    fi
    # The restart aborts an in-flight job (accepted — .env changes are rare); a
    # failed restart must be loud, or the content check above hides it forever.
    svc="$(runner_svc "$repo" "$i")"
    sudo systemctl restart "$svc" ||
      echo "  warn: ${svc} restart failed — new .env not applied" >&2
  done
}

# GitHub's anonymous abuse throttle answers a busy IP's git requests with an auth
# challenge, and every runner here shares taffy's egress IP with the gantry
# fleet: on 2026-09-02 gauntlet's CI died twice in `uv sync` fetching the PUBLIC
# djrhails-graphs source ("could not read Username for 'https://github.com'")
# while a sibling push six minutes later was green (DJRHails/gauntlet#57 has the
# probes). The helper answers that challenge with the public-read-only token
# set-github-token.sh installs — authenticated git is rate-limited per token,
# not per IP. Without the token it prints nothing, so a runner behaves exactly
# as before; a workflow fetching a PRIVATE git source still needs its own
# credential, because the token reads only what anyone can read, by design:
# every job on this host can read the file it lives in.
install_git_helper() {
  if ! sudo cmp -s "$GIT_HELPER_SRC" "$GIT_HELPER"; then
    echo ">> installing ${GIT_HELPER}"
    sudo install -D -m 0755 -o root -g root "$GIT_HELPER_SRC" "$GIT_HELPER"
  fi
  # The slot the token goes in, created before any token exists so `ls` on the
  # host reads "not installed yet" rather than "never wired up".
  sudo install -d -m 0750 -o root -g "$RUNNER_USER" "$GITHUB_TOKEN_DIR"
}

# Point every runner's own $HOME gitconfig at the helper, scoped to github.com.
# Converged per runner rather than seeded into a new HOME only, so pools
# provisioned before this existed get it too; git reads the file on every
# invocation, so no restart. Privileged probes, for the reason write_runner_envs
# gives.
write_runner_gitconfigs() {
  local repo="$1" n="$2" i dir cfg have
  for i in $(seq 1 "$n"); do
    dir="$(runner_dir "$repo" "$i")"
    cfg="${dir}/_home/.gitconfig"
    # No _home means no .env either — write_runner_envs already warned.
    sudo test -d "${dir}/_home" || continue
    have="$(sudo -u "$RUNNER_USER" git config -f "$cfg" --get credential.https://github.com.helper 2>/dev/null || true)"
    [ "$have" = "$GIT_HELPER" ] && continue
    echo "  ${repo#*/} runner-${i}: pointing git at ${GIT_HELPER##*/}"
    sudo -u "$RUNNER_USER" git config -f "$cfg" credential.https://github.com.helper "$GIT_HELPER"
  done
}

# A runner is healthy only if its unit is up AND anchored at the path we
# expect — a unit left at an old directory is silently the wrong runner.
# `activating` counts as up: with Restart=always a runner spends RestartSec
# windows there between an oom-kill and its comeback, and reinstalling one
# systemd is already restarting would deregister a runner that was about to
# recover on its own.
runner_is_healthy() {
  local svc="$1" want="$2" have state
  state="$(systemctl show -p ActiveState --value "$svc" 2>/dev/null || true)"
  case "$state" in active | activating | reloading) ;; *) return 1 ;; esac
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
    RU="$RUNNER_USER" HD="$RUNNER_HOME" TOKFILE="$tokfile" RMTOKFILE="$rmtokfile" \
    RESTART_DROPIN="$(restart_dropin_content)" bash <<'REMOTE'
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

  # Tear down whatever was there (an unregistered unit, or one anchored elsewhere).
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
  (cd "$DIR" && ./svc.sh install "$RU")
  # The drop-in goes on before the first start so a fresh runner is never
  # without the self-heal policy, not even for one job.
  install -d -m 0755 "/etc/systemd/system/${OLD}.d"
  printf '%s\n' "$RESTART_DROPIN" >"/etc/systemd/system/${OLD}.d/restart.conf"
  systemctl daemon-reload
  (cd "$DIR" && ./svc.sh start)
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
      # Privileged probe: /home/actions is 0750 actions:actions, so an
      # unprivileged `[ -x ]` is false for a script that exists, and the unit
      # would be left installed while the registration was deleted.
      if sudo test -x "${dir}/svc.sh"; then
        (cd "$dir" && sudo ./svc.sh uninstall) || true
      fi
      # svc.sh uninstall removes only the unit file; take our drop-in with it.
      sudo rm -f "/etc/systemd/system/${svc}.d/restart.conf"
      sudo rmdir "/etc/systemd/system/${svc}.d" 2>/dev/null || true
    fi
    # Deregister first, delete local state only on success — a swallowed
    # failure here (e.g. 422 on a busy runner) would orphan the registration
    # while destroying the credentials it needs to ever deregister itself.
    if ! gh api -X DELETE "repos/${repo}/actions/runners/${id}" >/dev/null; then
      echo "  warn: GitHub deregistration failed for ${name} (id ${id}) — keeping ${dir} for retry" >&2
      continue
    fi
    case "$dir" in
    "${RUNNER_HOME}"/?*) if sudo test -d "$dir"; then sudo rm -rf -- "$dir"; fi ;;
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
  ensure_restart_policy "$repo" "$n"
  indices="$(missing_indices "$repo" "$n" | tr '\n' ' ')"
  if [ -n "${indices// /}" ]; then
    install_runners "$repo" "$indices"
  else
    echo "  all ${n} runner(s) healthy"
  fi
  write_runner_envs "$repo" "$n"
  write_runner_gitconfigs "$repo" "$n"
  prune_runners "$repo" "$n"
}

main() {
  command -v gh >/dev/null || die "gh not found — run this on taffy with gh authed"
  [ -f "$CONF" ] || die "missing $CONF"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
  install_git_helper

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
