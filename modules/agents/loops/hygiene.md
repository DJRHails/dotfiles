# Loop: hygiene

Project-agnostic repo hygiene sweep (suggested cadence: every 4–6 h, or after a
push to the default branch). One iteration: sweep, then fix the single worst
finding. Default loop — works in any repo; reads the toolchain from the repo.

## State first

`rg '\[hygiene\]'` the repo's log (`EXPERIMENT_LOG.md` / `CHANGELOG.md` /
`docs/loop-log.md`). Anything found/fixed/deferred there is off the table unless
it's still the highest-value item.

Also check this loop's open PRs (`gh pr list --author @me`): one whose review has landed
gets resumed — address the feedback and judge the merge (see Merge gate) — before any new
sweep. That can be the whole iteration.

## Sweep (read-only, in order)

1. **Toolchain green.** Detect the stack and run its linter, formatter (check
   mode), type checker, and tests — e.g. Python `ruff check` / `ruff format
   --check` / `ty check` (or mypy) / `pytest -q`; Node `oxlint` (or eslint) /
   `tsc --noEmit` / `vitest run`; Rust `cargo clippy -- -D warnings` / `cargo fmt
   --check` / `cargo test`. A first-run red that's just missing dev deps → install
   them and note it, don't count it as a finding. Any real warning is a finding
   (zero-warnings policy).
2. **Untracked rot.** `git status --short` — untracked files older than a day get
   committed, folded into a tracked doc, or trashed. `*.local.json` / local
   settings must be gitignored.
3. **Stale generated artifacts.** Figures/build outputs whose generating script
   changed since the artifact was last committed — regenerate only when the change
   plausibly altered output.
4. **TODO/doc drift.** Checkboxes or docs contradicted by recent commits (done but
   unchecked, or checked but reverted).
5. **Worktrees.** List any `.git`/worktrees; flag merged/abandoned ones.

## Act

Fix the single worst finding completely (a red test beats a stale artifact beats
TODO drift). Defer the rest by listing them in the log entry. Never "fix" by
deleting a cache, weakening a test, or adding an ignore without a justification
comment.

## Write state back

Append a `[hygiene]` entry to the repo's log **only if something was found/fixed**
(no empty heartbeat entries). Ship it through the merge gate below. End with a ≤3-line status.

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
