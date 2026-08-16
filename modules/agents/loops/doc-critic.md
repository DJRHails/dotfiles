# Loop: doc-critic

Project-agnostic documentation-accuracy loop (suggested cadence: every 2–4 h, or
after a feature lands). One iteration: audit the repo's docs against the code as a
skeptical newcomer, then fix the single highest-value inaccuracy or gap (at most
two per run — a second only while the first's context is warm and a next-highest
item is already identified; never a third). Default loop — works in any repo.

## State first

`rg '\[doc-critic\]'` the repo's log. The docs touched by commits since the last
iteration are the priority surface; the rest is opportunistic. Also skim other
loops' entries in the same log for carried items overlapping your candidate
finding — if another loop (hygiene, research-critic, …) already carries it,
defer to that loop and pick the next-highest item instead. And skim the loop's
Slack channel for an uncommitted all-accurate record from the previous run (a
no-finding iteration reports there instead of opening a PR — see Act); carry it
into this iteration's loop-log entry.

Also check this loop's open PRs (`gh pr list --author @me`): one whose review has landed
gets resumed — address the feedback and judge the merge (see Merge gate) — before any new
audit. That can be the whole iteration.

## Audit (cheap checks first)

Re-read the README and the primary docs (the living/design docs, setup guide,
API reference) as someone who just cloned the repo:

- **Reproducibility.** Do the setup/build/test commands in the README actually
  work on a clean checkout? Run them. A command that no longer exists, a renamed
  script, a missing prerequisite is a finding.
- **Code/doc agreement.** Claims about behaviour, flags, file paths, or
  architecture that the code contradicts. Spot-check the load-bearing ones against
  the source — don't trust the prose.
- **Drift.** Features in recent commits that no doc mentions; docs describing
  removed/changed behaviour; dead links and stale references.
- **Calibration** (if the repo keeps a results/research doc): claims without the
  evidence or hedging the repo's own conventions require.

## Act

Fix the highest-value finding completely (then at most the one warm-context
second the intro sanctions) — a wrong setup command (blocks every newcomer)
beats a stale claim beats a dead link. Edit the code's
self-documentation only to state constraints, not to narrate. If a doc claim is
unverifiable, mark it as such rather than deleting it. If everything reads
accurate, say which docs are now trusted and at what depth — in the Slack
report only. Do **not** open a PR for a no-finding iteration: a
log-entry-plus-version-bump PR costs a review cycle and, on auto-deploying
repos, a control-plane restart. Carry the trusted-docs record into your next
finding PR's loop-log entry instead.

## Write state back

Only when a finding was fixed: append a `[doc-critic]` entry to the repo's log —
what was audited, the finding fixed, the next-highest item, plus any all-accurate
record carried from the previous run — and ship it through the merge gate below.
An all-accurate iteration writes no entry and opens no PR (see Act).
End with a ≤4-line status.

## Merge gate

1. **Open a PR** — never push straight to `main`, even on a solo repo. `git pull --rebase`
   before pushing the branch (loops run concurrently).
2. **Wait for a code review to land**: an approval **or** review comments. On repos with an
   auto-reviewer it usually shares your bot identity, so comments are the landed review
   (`reviewDecision` never reaches APPROVED — don't wait on it); check with
   `gh pr view --json reviews,comments`. Never busy-poll: if your harness has a wake
   primitive (gantry workers: `$GANTRY_WAKE_URL`), schedule one ~15 min out and end your
   turn; otherwise end the iteration — the next scheduled run resumes the PR via State first.
3. **Reviewed → address, then judge**: pull the branch (the reviewer may have pushed fix
   commits), address the feedback, then squash-merge a clean, low-risk, well-tested change
   you're confident in; leave anything uncertain or worth a human glance open. After your own
   feedback-fix push, allow one more wake/iteration for a follow-up review, then judge —
   don't loop forever.
4. **Never merge unreviewed.** No review after two checks — or no auto-reviewer on the repo
   at all — means leave the PR open for a human and say so in your report.
