---
name: github-actions
description: "Conventions for GitHub Actions workflow YAML in DJRHails repos — self-hosted taffy runners by default (GitHub-hosted minutes are billed), the fork guard for public repos, hermetic tooling because the runner has no sudo, and the cases that deliberately stay hosted. READ THIS BEFORE writing or editing any file under .github/workflows/, adding a job, changing runs-on, adding a CI step that installs a tool, or provisioning a runner."
---

# GitHub Actions conventions

**Default: jobs run on taffy's self-hosted pool. GitHub-hosted runners are billed
per minute and are the exception, taken deliberately and with a comment saying why.**

This exists because the account drifted to **$1.02/day** on hosted Linux minutes
while nominally "using self-hosted runners" — 61% of it one repo whose `ci.yml`
had never been migrated. Silent drift back to paid runners is the failure mode
every rule below is shaped against.

## The two `runs-on` forms

Copy one of these. Do not invent a third.

**Private repo:**

```yaml
    runs-on: >-
      ${{ vars.CI_FALLBACK == 'true'
      && 'ubuntu-latest'
      || fromJSON('["self-hosted", "linux", "x64", "taffy"]') }}
```

**Public repo whose workflow has a `pull_request` trigger** — a fork PR runs
arbitrary code and must never reach taffy:

```yaml
    runs-on: >-
      ${{ ((github.event_name == 'pull_request'
      && github.event.pull_request.head.repo.full_name != github.repository)
      || vars.CI_FALLBACK == 'true')
      && 'ubuntu-latest'
      || fromJSON('["self-hosted", "linux", "x64", "taffy"]') }}
```

A public workflow with no `pull_request` trigger (release, nightly sync) needs no
guard — only people with write access can fire it.

Two traps in that guard, both of which shipped broken once:

- **Compare repo names; never use `github.event.pull_request.head.repo.fork`.**
  That flag asks "is the head repo a fork *of anything*", not "did this PR come
  from elsewhere". `DJRHails/agent-browser` and `pi-interactive-subagents` are
  themselves forks of their upstreams, so the flag is permanently true there and
  routed **every** job to the billed runner — a silent, total no-op of the
  migration that only showed up by reading `.labels` on a finished job.
- **`github.event_name == 'pull_request' &&` is load-bearing.** On push,
  `github.event.pull_request` is null, so `head.repo.full_name` is null, and
  `null != 'DJRHails/repo'` is **true** — without the event check, every push
  would route to hosted.

**The `runs-on` guard is defence in depth, not the control.** A `pull_request`
run executes the PR's *own* copy of the workflow file, so a fork PR can simply
edit `runs-on` back to the taffy label. What actually enforces it is the repo's
fork-PR approval policy — review the workflow diff before approving a fork PR's
run:

```sh
gh api repos/DJRHails/<repo>/actions/permissions/fork-pr-contributor-approval \
  --jq .approval_policy                       # want: all_external_contributors
gh api -X PUT repos/DJRHails/<repo>/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
```

Set that on any public repo before pointing a `pull_request` job at the pool.

Three details that are easy to get wrong:

- **Use the folded `>-` block, and keep every continuation line at the same
  indent.** YAML only folds lines at equal indentation; a more-indented
  continuation is preserved *literally*, leaving real newlines inside the
  `${{ }}`. Verify with a YAML parse, not by eye.
- **Polarity is `== 'true'`, never `!= 'false'`.** Unset must mean self-hosted.
  The inverse fails toward *silently spending money*, which is the exact drift
  this convention exists to prevent. (gantry's `check.yml` uses `!= 'false'`
  deliberately, because the watcher below actively manages that repo — don't
  copy it elsewhere.)
- **Never add `github.run_attempt > 1` as a second hatch.** It reads as a
  friendly "re-run to escape a sick runner", but it assumes hosted capacity
  exists. When the account's billing lapses or its spending limit trips, every
  hosted job fails in ~2s with zero steps — so the natural retry gesture becomes
  a *guaranteed* red with no route to green. That reddened gantry#686 twice with
  no code fault. A re-run on the taffy label is re-dispatched across the pool and
  can land on a healthy sibling.

Also put `timeout-minutes` on every job. Without it a wedged job inherits
GitHub's 6-hour default.

## When to stay GitHub-hosted — and say so in a comment

An unexplained `ubuntu-latest` reads as an oversight and *will* get "fixed" by
the next sweep. If a job must stay hosted, write the reason on the job.

| stay hosted when | why | example |
| --- | --- | --- |
| the job executes untrusted code | the ephemeral VM **is** the sandbox's outer half; taffy is persistent, shared, and its runner user is in `docker` (root-equivalent) | bestiary's malware detonation workflows |
| a fork PR on a public repo | same, via the fork guard above | graphs, agent-browser |
| the job holds a publishing credential | a PyPI/registry token — even short-lived OIDC — shouldn't sit on a host running every other pooled repo's CI as the same user | emboss, graphs `Release to PyPI` |
| the platform isn't in the pool | there are no macOS or Windows self-hosted runners | agent-browser's Windows and cross-platform matrices |
| output is pinned to the runner image | visual goldens rendered by that image's driver stack will not reproduce elsewhere | decal's SwiftShader `e2e` job |

Cost is not the only axis. A rare job buying real isolation is worth its minutes.

## The runner has no sudo — make tooling hermetic

The `actions` user on taffy has **no passwordless sudo**, and no `uv`, `go`,
`pipx`, `cargo`, `bun` or `actionlint` on PATH. It *does* have git, curl, node,
pnpm, python3, docker, jq, tar/xz, rg and gh.

So these all fail on the pool:

```yaml
- run: sudo apt-get install -y shellcheck      # no sudo
- run: go install .../actionlint@v1.7.12       # no go
- run: pipx run ruff==0.15.17 check .          # no pipx
```

Provision tools **in the workflow**, so the job behaves identically on the pool
and on a hosted fallback:

- a `setup-*` action (`astral-sh/setup-uv`, `actions/setup-node`,
  `pnpm/action-setup`) — pin the action by SHA and pin the tool version too
- `uvx <tool>@<version>` once `setup-uv` has run — the `pipx run` replacement
- otherwise a pinned release binary into `$RUNNER_TEMP/bin`, **verified against a
  sha256 you recorded**: a release asset can be re-uploaded without its tag
  moving, and these binaries execute on a persistent shared host

Relying on the host having a tool is the same class of bug in reverse — it works
on taffy and breaks the moment `CI_FALLBACK` sends the job to a hosted runner.

Things that *do* work unchanged on the pool: `services:` containers, job-level
`container:`, `cache:` on the setup actions, `type=gha` buildx cache, and OIDC.

## Never write secrets to `$HOME` on a self-hosted runner

On a hosted runner `$HOME` dies with the VM. On taffy it belongs to the shared
`actions` user and **persists across jobs and across every repo with a pool
there**. A deploy key written to `~/.ssh/` outlives the run and is readable by
unrelated CI.

Write to `$RUNNER_TEMP` (wiped between jobs), and pass the secret through `env:`
rather than interpolating `${{ secrets.X }}` into a script body:

```yaml
      - name: Deploy
        env:
          DEPLOY_KEY: ${{ secrets.BONBON_DEPLOY_KEY }}
        run: |
          set -euo pipefail
          key="${RUNNER_TEMP}/key"; known="${RUNNER_TEMP}/known_hosts"
          install -m 600 /dev/null "$key"
          printf '%s\n' "$DEPLOY_KEY" >"$key"
          ssh-keyscan -H "$HOST" >"$known" 2>/dev/null
          ssh -i "$key" -o IdentitiesOnly=yes -o UserKnownHostsFile="$known" ...
```

## Runner pools

Pools are declared in
[`modules/ci-runners/runners.conf`](../../../ci-runners/runners.conf) and
reconciled by `provision.sh` **run on taffy**:

```sh
./provision.sh                       # reconcile every repo in the conf
./provision.sh DJRHails/<repo>       # just one
```

Personal accounts cannot have account-level runners, so **every repo needs its
own registration** — adding a `runs-on` pointing at `taffy` in a repo with no
pool means jobs queue against a label nothing answers. Add the repo to
`runners.conf` and provision *before* merging the workflow change.

Size the pool to the widest fan-out in the repo's workflows: a 2-job CI wants 2
runners or the second job waits.

Deploy jobs that must run *on* a prod host keep their existing
`[self-hosted, linux, deploy]` labels — taffy is for build and test, not prod.

## `CI_FALLBACK` and the watcher — do not opt new repos in

`bonbon` runs `ci_fallback_watch.sh` (from the gantry checkout) on a 2-minute
cron. It flips `CI_FALLBACK` from taffy runner online-status for exactly three
repos: **gantry, decal, hails.info**. Leave those three alone; their `runs-on`
is tuned to it.

Do **not** add new repos. That watcher is what "burned 11,020 hosted minutes off
touchstone during the Aug 2-4 taffy OOM window and tripped the ACCOUNT-level
spending limit, blocking every repo" (its own docstring, touchstone#2734). For
everything else `CI_FALLBACK` stays a manual, deliberate switch, so a taffy
outage **queues** jobs — visible and free — instead of silently billing.

touchstone and bogusbench go further and are hard-pinned to the pool with no
hosted fallback at all (the 2026-08-05 owner call).

## Before you commit a workflow change

```sh
actionlint .github/workflows/*.yml     # not the directory — it wants the glob
zizmor .github/workflows/              # global standard
```

and confirm the `runs-on` expression parsed to a single line with no embedded
newline. After merging, check where the job actually landed rather than assuming:

```sh
gh api "repos/DJRHails/<repo>/actions/runs/<id>/jobs" \
  --jq '.jobs[] | "\(.name)\t\(.conclusion)\trunner=\(.runner_name)"'
```

The `runs/<id>/timing` endpoint reports `total_ms: 0` for recent runs — it is not
a usable source for billed minutes. To attribute spend, use the billing page's
own endpoints (`/settings/billing/usage_table?group=4&period=3` groups by repo,
but caps at the top 5 and lumps the rest into an `other` bucket).
