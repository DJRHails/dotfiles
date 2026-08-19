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
cost of not moving 20 repos into an org.

**A `runs-on` pointing at the `taffy` label in a repo with no pool does not fall
back — it queues against a label nothing answers, and `timeout-minutes` does not
bound queue time.** Provision before merging the workflow change.

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

- a runner is **(re)installed** when its unit is missing, dead, or anchored at
  the wrong directory,
- runners with an index **above** the configured count are stopped and
  deregistered — so lowering a number in `runners.conf` is how you shrink a pool,
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
