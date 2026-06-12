# Loop: perf-bestofn

Project-agnostic best-of-N performance loop (suggested cadence: every 2–4 h, or
on demand after a slow run). One iteration = one measured bottleneck → N
independent candidate fixes raced in isolation → benchmark all → merge only the
winner. Never ship an unmeasured optimisation. Default loop — works in any repo.

## State first

`rg '\[perf-bestofn\]'` the repo's log — bottlenecks already attacked (won or
written off) are off the table unless new evidence reopens them.

## Find the bottleneck (measure, don't guess)

Profile or mine timings (test runtimes, build logs, a representative workload) for
the single biggest wall-clock sink in a hot path. Classify it before touching
code: CPU/algorithmic, IO/serialisation, network/IO-bound, or
cache/recompute-bound. State the metric you'll move (wall-clock on a fixed
workload, throughput, allocations) and how you'll measure it. If nothing is worth
attacking (best candidate <10% of the workload), log that and stop — don't invent
work.

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
cache-invalidation cost; tie-break by smaller diff. Merge the winner; discard the
rest (keeping any reusable idea in the log).

## Write state back

Append a `[perf-bestofn]` entry to the repo's log: bottleneck, the N tacks, a
benchmark table (baseline + each candidate), winner and why, losers' ideas worth
keeping. Always **open a PR** (never push straight to `main`, even on a solo repo); then use your judgement on whether to merge it — squash-merge a clean, low-risk, well-tested change you're confident in, and leave anything uncertain or worth a human glance open. `git pull --rebase` before pushing the branch (loops run concurrently). End with a ≤5-line status.
