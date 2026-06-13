# Loop: perf-bestofn

Project-agnostic best-of-N performance loop (suggested cadence: every 2–4 h, or
on demand after a slow run). One iteration = one measured bottleneck → N
independent candidate fixes raced in isolation → benchmark all → merge only the
winner. Never ship an unmeasured optimisation. Default loop — works in any repo.

## State first

`rg '\[perf-bestofn\]'` the repo's log — bottlenecks already attacked (won or
written off) are off the table unless new evidence reopens them.

Also check this loop's open PRs (`gh pr list --author @me`): one whose review has landed
gets resumed — address the feedback and judge the merge (see Merge gate) — before any new
race. That can be the whole iteration.

## Find the bottleneck (measure, don't guess)

Profile or mine timings for the single biggest wall-clock sink in a hot path.
**If the repo is a deployed service, prefer its production telemetry over
synthetic benchmarks** — that's where real bottlenecks surface: operation/request
latencies in its logs, and run durations/costs/queue-waits in its datastore or
event log. Otherwise use test runtimes, build logs, or a representative workload.
Classify the sink before touching code: CPU/algorithmic, IO/serialisation,
network/IO-bound, or cache/recompute-bound. State the metric you'll move
(wall-clock on a fixed workload, throughput, allocations, p50/p95 latency) and how
you'll measure it. If you can measure and nothing is worth attacking (best
candidate <10% of the workload), log that and stop — don't invent work. But if you
*can't* localise the sink because the signal isn't there, instrument first (next)
rather than calling it done.

## Instrument first when production isn't traced

If the production signal you'd measure against is missing or too thin to localise a
bottleneck — no per-operation timing in the logs, logs are ephemeral (lost on
restart, not queryable), outputs aren't traced — then **adding that instrumentation
is the iteration**. Trace production outputs durably and structured: timing spans
around the hot operations, p50/p95 latency, per-operation durations/costs, written
somewhere queryable (a persistent log file/sink, the service's datastore, or a
metrics surface) rather than only stdout. Keep it cheap (sampled or async if hot)
and **never log secrets** — route any line that could carry a token/env through the
repo's redactor. This is a complete, high-value pass on its own: skip the candidate
race this round and log what is now traceable, so the next iteration can measure and
optimise against real numbers. Don't optimise blind — an unmeasurable change can't
qualify under "Pick the winner".

## Generate N candidates in parallel

Spawn ~3 isolated attempts (worktrees / branches), same bottleneck brief, a
**different tack each** (better algorithm/data structure vs caching/memoisation vs
batching/parallelism vs avoiding the work). One tack per attempt; each must:
implement it, run the agreed benchmark ≥3× (fixed input, stated warm/cold state),
and confirm outputs are unchanged (tests pass, results identical to baseline).

## Pick the winner

Baseline-benchmark first with the same command. A candidate qualifies only if
tests pass, outputs match, and the gain exceeds noise (≥10% or clearly outside
run-to-run spread). Rank qualifiers by measured gain minus any added complexity /
cache-invalidation cost; tie-break by smaller diff. The winner becomes the PR; discard
the rest (keeping any reusable idea in the log), but keep the winner's worktree until
its PR merges — the resumed iteration needs it to address review feedback.

## Write state back

Append a `[perf-bestofn]` entry to the repo's log: bottleneck, the N tacks, a
benchmark table (baseline + each candidate), winner and why, losers' ideas worth
keeping. Ship it through the merge gate below. End with a ≤5-line status.

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
