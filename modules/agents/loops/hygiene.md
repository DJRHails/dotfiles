# Loop: hygiene

Project-agnostic repo hygiene sweep (suggested cadence: every 4–6 h, or after a
push to the default branch). One iteration: sweep, then fix the single worst
finding. Default loop — works in any repo; reads the toolchain from the repo.

## State first

`rg '\[hygiene\]'` the repo's log (`EXPERIMENT_LOG.md` / `CHANGELOG.md` /
`docs/loop-log.md`). Anything found/fixed/deferred there is off the table unless
it's still the highest-value item.

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
(no empty heartbeat entries). Commit + push (`git pull --rebase` before pushing —
loops push concurrently). End with a ≤3-line status.
