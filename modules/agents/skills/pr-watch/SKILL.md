---
name: pr-watch
description: Watch a set of GitHub PRs and get one notification per change — CI pass/fail, merge conflicts, reviews (approve / changes requested), new review threads, comments, merge-queue drops, merges. Use when asked to "monitor / keep an eye on / watch" PRs, to babysit PRs through review and the merge queue, or to merge PRs as they get approved. Feeds Claude Code's Monitor tool; includes the playbook for acting on each event.
---

# pr-watch

`scripts/pr-watch` polls PRs over GraphQL and prints **one line per new fact** — the diff between
consecutive snapshots. Pipe it into the Monitor tool and each line becomes a notification.

```bash
~/.agents/skills/pr-watch/scripts/pr-watch --repo OWNER/NAME --requeue 13029 12931 12408
~/.agents/skills/pr-watch/scripts/pr-watch --author @me --requeue --merge-approved  # merge mine as approved
~/.agents/skills/pr-watch/scripts/pr-watch --once 13029               # one pass, for testing
```

Arm it with Monitor at the 30-minute maximum and re-arm on each expiry notice. Snapshots persist
in `~/.cache/pr-watch/<owner>_<repo>/`, so a re-arm resumes silently instead of replaying history,
and the first pass over a new PR only records a baseline. `--author` is re-resolved every pass,
so new PRs join and merged ones drop out. `--state-dir` isolates a watch from earlier ones.

**When the user says "my PRs", watch `--author @me`, not a fixed list of numbers.** A fixed list
silently misses every PR opened after the watch starts. Add explicit numbers only for other
people's PRs. When they ask to merge PRs as they get approved, add `--merge-approved`: it turns on
auto-merge for the user's own approved, non-conflicting PRs (never anyone else's), including PRs
already approved when the watch starts. It never re-adds a PR the merge queue dropped: timeouts
are `--requeue`'s job, and any other drop needs its failing check read first.

## Events

| line | meaning |
|---|---|
| `ci=SUCCESS` / `ci=FAILURE` / `ci=ERROR` | latest commit's rollup settled (`PENDING` is suppressed) |
| `CONFLICTING` | no longer merges cleanly with its base |
| `review <id> <login> APPROVED\|CHANGES_REQUESTED\|COMMENTED` | a new review (the PR author's own are skipped) |
| `now APPROVED` | review decision flipped to approved — merge-ready once CI passes |
| `open-thread <id> last-by=<login>` | a new unresolved thread, or a reply on one |
| `comment <id> <login>` | new top-level comment from someone else |
| `removed-from-merge-queue <at> <reason>` | `merged`, or a drop such as `checks_timed_out` |
| `approved; auto-merge enabled` | `--merge-approved` queued one of your approved PRs |
| `requeued after checks_timed_out` | `--requeue` put an approved PR back in the queue |
| `state=MERGED` / `state=CLOSED` | done; the PR is dropped from the watch |
| `snapshot failed: <error>` | `gh` could not read the PR (typo'd number, auth, rate limit); printed once per failure streak |

## Acting on events

- **Before touching a branch, check it is still yours to touch.** On a repo with parallel sessions
  another session may be reshaping it: compare `gh pr view N --json headRefOid` with the SHA you
  last pushed and `git log` what landed. Push only with
  `--force-with-lease=<branch>:<sha you started from>`, never a bare force.
- **`CONFLICTING`**: rebase in a fresh worktree off `origin/<branch>`; regenerate generated files
  instead of hand-merging; restack dependents bottom-up. If someone else pushed in the last hour,
  ask before rebasing over it.
- **New threads / `CHANGES_REQUESTED`**: verify each claim (a failing test first), fix or explain,
  then reply to every thread *before* resolving it. Re-requesting a human's review
  (`gh api -X POST repos/O/R/pulls/N/requested_reviewers -f 'reviewers[]=login'`) notifies them —
  confirm with the user first on shared repos.
- **`now APPROVED`**: if the user asked to merge as approved, `gh pr merge N --auto` (merge-queue
  repos pick the strategy themselves; `--squash` prints a harmless note). Only for the user's own
  PRs unless told otherwise — a teammate's approved PR is theirs to merge.
- **`removed-from-merge-queue … checks_timed_out`**: a congested queue, not a code failure; re-add
  with `gh pr merge N --auto` (or run with `--requeue`). Any other reason: read the failing check.
- **`ci=FAILURE`**: `gh pr checks N`, then the failing job's log; tell flakes (timeouts, cold-start
  JIT) from real failures before re-running.

A silent 30 minutes is normal while waiting on humans or a long queue. If something should have
happened, run one `--once` pass with a fresh `--state-dir` and read the raw snapshot.
