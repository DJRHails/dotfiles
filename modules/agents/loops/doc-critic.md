# Loop: doc-critic

Project-agnostic documentation-accuracy loop (suggested cadence: every 2–4 h, or
after a feature lands). One iteration: audit the repo's docs against the code as a
skeptical newcomer, then fix the single highest-value inaccuracy or gap. Default
loop — works in any repo.

## State first

`rg '\[doc-critic\]'` the repo's log. The docs touched by commits since the last
iteration are the priority surface; the rest is opportunistic.

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

Fix the single highest-value finding completely — a wrong setup command (blocks
every newcomer) beats a stale claim beats a dead link. Edit the code's
self-documentation only to state constraints, not to narrate. If a doc claim is
unverifiable, mark it as such rather than deleting it. If everything reads
accurate, say which docs are now trusted and at what depth.

## Write state back

Append a `[doc-critic]` entry to the repo's log: what was audited, the finding
fixed (or "accurate"), the next-highest item. Always **open a PR** (never push straight to
`main`, even on a solo repo). Opening it triggers an automated code review — never merge
before a review lands as an approval or review comments (`gh pr view --json
reviews,comments,reviewDecision`; schedule a wake rather than busy-polling). Once reviewed,
pull the branch (the reviewer may push fix commits), address the feedback, then use your
judgement — squash-merge a clean, low-risk, well-tested change you're confident in, and leave
anything uncertain or worth a human glance open. No review after two wakes: leave the PR open
and say so. `git pull --rebase` before pushing the branch (loops run concurrently).
End with a ≤4-line status.
