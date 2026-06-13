# Default loops

Reusable, **project-agnostic** loop definitions, shared across coding agents the
same way `subagents/` and `skills/` are (`symlinks.conf` links this dir into
`~/.agents/loops`, `~/.claude/loops`, `~/.claude-ant/loops`). Because worker
images bake the dotfiles, every worker has these at a known path — so a scheduled
loop can reference a default loop here without the target repo carrying its own.

## What a loop is

A loop is a **single, self-contained iteration prompt**: one file that tells an
agent how to do one bounded pass over a repo — read state first (so iterations
don't repeat work), do exactly one improvement, write state back (log + commit +
push). A scheduler (cron, the portcullis loop scheduler, or `/loop`) runs the
file on an interval; the file is the whole contract, so editing the loop is
editing one file.

## Using a default loop

- **As-is:** point a schedule at `~/.agents/loops/<name>.md` (e.g. `hygiene` works
  in any repo). The worker reads it and runs one iteration in whatever repo it's
  checked out in.
- **Specialised:** copy it into a repo's `docs/loops/<name>.md` and tailor it.
  Project-specific loops (tied to a particular dataset, research doc, or harness)
  live in the repo, not here — only genuinely generic loops belong in dotfiles.

## Shared conventions (every loop)

1. **State first** — read the repo's loop ledger (`rg '\[<name>\]'` in the
   experiment/change log) so the iteration continues rather than repeats, and resume any
   open PR from a previous iteration (`gh pr list --author @me`) whose review has landed
   before starting new work — that can be the whole iteration.
2. **One improvement** — pick the single highest-value item and finish it (code,
   test, doc); don't start a second.
3. **Write state back** — record the iteration in the repo's log if it has one
   (`EXPERIMENT_LOG.md`, `CHANGELOG.md`, else a `[<name>]` line in a `docs/loop-log.md`),
   commit small, and ship it through the **merge gate** (a verbatim-identical section in
   each loop file): open a PR (never push straight to `main`); wait for a code review to
   land — an approval **or** review comments (the auto-reviewer usually shares the bot
   identity, so `reviewDecision` never reaches APPROVED) — without busy-polling (gantry
   workers schedule a `$GANTRY_WAKE_URL` wake; wake-less schedulers just end the iteration
   and resume via State first); once reviewed, pull the branch, address feedback, then
   judge the squash-merge; **never merge unreviewed** — no review after two checks, or no
   auto-reviewer at all, means leave the PR open for a human and say so.
   Also report findings to the loop's Slack channel — the scheduler's wrapper names it and
   posts a start-ping there.
4. **Guardrails** — never weaken a test or delete a cache to make a check pass;
   smoke-test before any long run; respect the repo's own AGENTS.md/CLAUDE.md.

## The defaults here

- **`hygiene`** — toolchain/format/test/stale-artifact sweep; fix the worst finding.
- **`doc-critic`** — audit the repo's docs/README against the code; fix the
  highest-value inaccuracy or gap.
- **`perf-bestofn`** — measure the top bottleneck, race N candidate fixes in
  isolation, merge the winner.
