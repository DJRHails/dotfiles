# spend-watch

Daily GitHub metered-spend digest to the (solo) hails-talk **#spend** channel.

Nobody was watching this. The account sat at roughly **$1.02/day** of
GitHub-hosted Actions minutes for weeks while nominally "using self-hosted
runners" — 61% of it one repo whose `ci.yml` had never been migrated — and the
only reason it surfaced was someone opening the billing page. A repo whose
`runs-on` quietly points back at a billed runner is otherwise invisible.

The routing conventions this watches over live in the
[`github-actions` skill](../agents/skills/github-actions/SKILL.md); the runner
pools it protects live in [`ci-runners`](../ci-runners/README.md).

## What it posts

```
*GitHub metered spend — 2026-08-18*
Billed that day: *$2.42* — :red_circle: over the $0.50/day target
Month to date: $60.90 over 20 days ($3.04/day average)

By repo:
  gauntlet  $1.85
  bestiary  $0.43
  isogram  $0.05
```

Net (post-discount) dollars — what actually gets billed. Repos under a cent are
folded away, so a fully self-hosted day reads
`(nothing above a cent — all self-hosted)`.

## Running it

```sh
bash modules/spend-watch/spend_watch.sh              # yesterday, once per day
bash modules/spend-watch/spend_watch.sh 2026-08-18   # re-render a given day
```

Passing a date ignores the once-per-day marker, which is how you test it.

Installed as a cron on **bonbon** (which already hosts `uptime_watch` and the
`#alerts` plumbing):

```
15 9 * * *   # 09:15 UTC — late enough that the previous UTC day is settled
```

The marker at `~/.local/state/spend-watch/last_posted` is written **only after a
confirmed Slack post**, so a failed send retries on the next run instead of
silently burning that day's one digest. It also makes a doubled cron entry safe.

## The `user` scope

The enhanced-billing REST API (`/users/{user}/settings/billing/usage`) needs a
token with the **`user`** scope. A plain `repo`+`workflow` token — which is what
`gh` is normally set up with — returns a bare `404` plus a scope hint on stderr,
which reads like "no such billing data" rather than "wrong token". The script
surfaces that stderr instead of swallowing it.

Grant it with:

```sh
gh auth refresh -h github.com -s user
```

Or point the script at a different token with `GH_BILLING_TOKEN`.

## Config

| variable | default | meaning |
| --- | --- | --- |
| `SPEND_WATCH_USER` | `DJRHails` | account to report on |
| `SPEND_WATCH_CHANNEL` | `C0BRE67340K` | `#spend` in hails-talk |
| `SPEND_WATCH_TARGET` | `0.50` | dollars/day before the digest goes red |
| `SPEND_WATCH_ENV` | touchstone `.env` | where `SLACK_BOT_TOKEN` is read from |
| `GH_BILLING_TOKEN` | gh's own token | override for the billing API call |
