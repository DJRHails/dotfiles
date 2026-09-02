# ci-runners

Self-hosted GitHub Actions runner pools on **taffy**, declared in
[`runners.conf`](./runners.conf) and reconciled by [`provision.sh`](./provision.sh).

GitHub-hosted runner minutes are billed; taffy's are free. Every repo that runs
CI should have a pool here. The workflow-side conventions — which `runs-on` form
to use, when a job should deliberately *stay* hosted, and why the runner has no
sudo — live in the [`github-actions` skill](../agents/skills/github-actions/SKILL.md).

## Why per-repo

A personal account cannot have account-level runners; only orgs get runner
groups. So every repo needs its own registration, and taffy carries one
`actions.runner.DJRHails-<repo>.taffy-<i>` systemd unit per runner. That is the
cost of not moving ~20 repos into an org.

**A `runs-on` pointing at the `taffy` label in a repo with no pool does not fall
back — it queues against a label nothing answers, and `timeout-minutes` does not
bound queue time.** Provision before merging the workflow change.

## Finding repos that need a pool

**Scope off the billing data, never off "recently pushed".** The first sweep
listed candidates with `user/repos?sort=pushed` filtered to the last ~10 days,
which silently missed five private repos — `words.hails.info`, `api.hails.info`,
`takete`, `baton`, `survey.hails.info` — whose workflows are deploy- or
schedule-triggered and were billing steadily without anyone committing to them.
A repo can spend money for months without a single push.

The billing API is the complete list, and it also tells you which repos are
*worth* migrating — public repos net $0 no matter how many minutes they burn:

```sh
gh api "users/DJRHails/settings/billing/usage?year=$(date +%Y)&month=$(date +%-m)" |
  jq -r '[.usageItems[]|select(.sku|startswith("Actions"))]
    | group_by(.repositoryName)
    | map({r:.[0].repositoryName, net:(map(.netAmount)|add)})
    | sort_by(-.net) | .[] | select(.net > 0) | "\(.r)\t$\(.net*100|round/100)"'
```

The SKU match is a prefix on purpose: an exact `sku=="Actions Linux"` silently
drops macOS (10× the Linux rate), Windows, and larger-runner SKUs — the same
silent-scoping mistake in a smaller box. Storage rows ride along at pennies,
which errs toward over-reporting, the right direction for an audit.

Needs a token with the `user` scope (see [`spend-watch`](../spend-watch/README.md)).
Cross-check each against `gh api repos/DJRHails/<r>/actions/runners`.

## Usage

Run **on taffy** (needs local `gh` auth to mint registration tokens, and
passwordless sudo for the service user and units):

```sh
cd ~/.files/modules/ci-runners
./provision.sh                     # reconcile every repo in runners.conf
./provision.sh DJRHails/gauntlet   # just one, count from the conf
./provision.sh DJRHails/gauntlet 6 # just one, count overridden
```

Idempotent and convergent:

- every managed unit gets the **self-heal drop-in**
  (`/etc/systemd/system/<unit>.d/restart.conf`: `Restart=always`, rate-limited
  by `StartLimit*`, plus `OOMPolicy=continue` and `KillMode=mixed`) (re)written
  first — `svc.sh` emits a unit with no `Restart=`, so without it the first
  oom-kill on the memory-overcommitted host parks the runner in `failed` until a
  human reaches taffy (touchstone lost three of four runners that way overnight
  on 2026-08-31). `OOMPolicy=continue` is the other half: under systemd's default
  `stop`, an oom-killed *job step* stops the whole runner and spends one of its
  rate-limited starts (touchstone taffy-2 reached "restart counter is at 6"
  on 2026-09-02), and five such bounces inside five minutes latch the runner
  offline with its registration intact. `KillMode=mixed` closes the last gap:
  `svc.sh`'s template uses `KillMode=process`, so a stop or a dead `runsvc.sh`
  left the listener/worker tree alive and the next start ran a second listener
  beside it — every job on that runner then set up twice in one directory and
  died in seconds with `_diag/pages/…_1.log already exists` (touchstone
  taffy-4 and taffy-2, 2026-09-02, a minute after a revive-in-place),
- a unit in `failed` whose registration is still intact (`.runner` on disk
  **and** the name still in GitHub's runner list) is **reset and started**,
  keeping its `_diag` logs; a runner is **(re)installed** only when its unit is
  missing, unregistered, or anchored at the wrong directory,
- runners with an index **above** the configured count are stopped and
  deregistered — so lowering a number in `runners.conf` is how you shrink a
  pool, and count `0` drains it. **Deleting a repo's line does not**: the
  reconciler only visits repos listed in the conf, so removed lines leave their
  runners running unmanaged,
- pruning is driven by GitHub's runner list — a local unit GitHub no longer
  knows about (registration deleted in the UI) must be removed by hand,
- `prod-*` runners are never touched (only `taffy-<i>` names are managed).

## Layout

Each runner runs as the non-root `actions` user, in the `docker` group so it
drives taffy's shared host daemon:

```
/home/actions/<repo>-runner-<i>/                        runner install
/etc/systemd/system/actions.runner.DJRHails-<repo>.taffy-<i>.service
```

Units are `enabled`, so pools survive a reboot.

## Checking on it

```sh
systemctl list-units 'actions.runner.*' --no-pager
gh api repos/DJRHails/<repo>/actions/runners \
  --jq '.runners[] | "\(.name) \(.status) busy=\(.busy)"'
```

## Sizing

`<count>` is the ceiling on concurrent jobs for that repo, so it must be at
least the widest fan-out in its workflows — a 2-job CI with 1 runner serialises.
An idle runner is ~120 MB and taffy has 48 cores / 125 GB, so round up.

## What the runner does *not* have

No passwordless sudo, and no `uv`, `go`, `pipx`, `cargo`, `bun` or `actionlint`.
Workflows must provision their own tooling — see the skill. Deliberately not
fixed by preinstalling: a workflow that leans on host state breaks the moment
`CI_FALLBACK` sends it to a GitHub-hosted runner.
