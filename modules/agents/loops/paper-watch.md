# Loop: paper-watch

Project-agnostic paper-curation loop for research repos (suggested cadence: daily).
One iteration: sweep recent arXiv for papers relevant to this repo's research
questions, curate the handful worth the maintainer's attention, write them up
under `docs/paper-watch/`, and post the picks to the loop's Slack channel. Works
in any repo whose README / RESEARCH.md / PLAN.md states what the project is about.

## State first

Read `docs/paper-watch/` in the repo:

- **`queries.md`** — the standing search brief: arXiv queries + categories, the
  key papers whose citing works matter, and a relevance rubric. Missing → this
  is the loop's first run in this repo; derive it (see First run) before sweeping.
- **`ledger.jsonl`** — every paper already triaged, one JSON object per line:
  `{"id": "2508.01234", "title": "…", "run": "YYYY-MM-DD", "verdict": "curated" | "passed" | "implementing"}`
  (`implementing` entries also carry `"thread": "thrd_…"`, the spawned run).
  Never re-triage an id that appears here, whatever its verdict — the daily
  windows overlap by design and the ledger is what makes that cheap.

Also check this loop's open PRs (`gh pr list --author @me`): one whose review has
landed gets resumed — address the feedback and judge the merge (see Merge gate) —
before any new sweep. That can be the whole iteration. An open paper-watch PR that
hasn't been reviewed yet still holds the freshest ledger: sweep against its
branch's `ledger.jsonl` and stack the new writeup onto that same branch — never
sweep against the stale copy on `main`.

## First run (no queries.md)

Read the repo's own statement of intent — README, RESEARCH.md / PLAN.md /
PITCH.md, `references.bib` — and distil `docs/paper-watch/queries.md`:

- 4–8 arXiv search queries (keywords + categories, e.g. `cs.AI cs.CL cs.LG cs.CR`);
- the 3–5 anchor papers whose citing works are worth watching;
- a one-paragraph relevance rubric: "a paper is relevant iff …", naming the
  repo's live research questions.

`queries.md` is the loop's steering surface — a human editing it retargets every
future run, so keep it short and legible. The first sweep backfills the last
**6 months**; every later run covers the last **7 days**.

## Sweep

Use the arxiv skill (the plain arXiv REST API — no key). For each query in
`queries.md`, pull submissions inside the window, plus (when cheap) new citers
of the anchor papers via Semantic Scholar. Drop everything already in the
ledger, then triage the remainder by title + abstract against the rubric.
Shortlist aggressively: a weekly window should curate ≤ 12 papers (a 6-month
backfill ≤ 25) — if more clear the bar, raise the bar and say so in the writeup.
For each curated paper, read the abstract (skim the intro if the abstract is
ambiguous) — enough to say something a title alone couldn't.

## Write up

Write `docs/paper-watch/YYYY-MM-DD.md` (run date), grouped under descriptive
theme headings, opening with one line of run facts (window, candidates seen,
curated count). Per paper:

- `### [Title](https://arxiv.org/abs/<id>)` — first author et al., month.
- 2–4 sentences: the claim, the evidence, and **why it matters to this repo** —
  name the specific doc, benchmark, experiment, or design decision it touches.
- A suggested action: cite, compare against, steal the method, replicate, or
  just be aware of.

Append every triaged paper (curated *and* passed) to `ledger.jsonl`.
Don't edit `references.bib` — flag citable papers in the writeup instead.

## Escalate to an implementation run

A curated paper can cross a second, higher bar: its method is implementable
inside this repo's own harness **and** landing it would move something the
repo's docs already care about — a benchmark the plan calls for, a baseline or
ablation to compare against, an eval or training technique to adopt. Candidates
are this run's curated papers plus recent `curated` ledger entries (the sweep's
dedup hides those — re-read the last few writeups when picking). For at most
**one** such paper per iteration:

- Check it isn't already in flight: no open PR mentioning the paper
  (`gh pr list --search <id-or-keyword>`), no `implementing` ledger entry.
- Spawn a peer worker to build it — gantry workers hold spawn scope
  (the CLI rides `$GANTRY_API_KEY`):
  `gantry spawn djrhails-dev "<brief>" --repo <owner>/<repo>`. The brief must
  be self-contained: arXiv id + title + link, what to implement and where it
  lands in the repo, acceptance criteria (tests, eval numbers, or a doc'd
  comparison), and the instruction to ship as a PR on a branch — never push to
  `main`, never merge unreviewed.
- Record it: ledger verdict `implementing` with the spawned `thread` key, and
  name the spawned run in the writeup entry and the Slack message.

When in doubt, don't spawn — a wasted implementation run costs more than a
missed paper, and a later run can still escalate it from the ledger.

## Report to Slack

Post **one** message to the loop's Slack channel (named in your wrapper task)
via the slack skill: the top ≤ 8 picks, each a linked title plus a one-line
why-it-matters, ending with a link to the writeup (the PR if not yet merged).
Link every reference inline. Never paste repo-private content — task text,
certificates, pressure prompts, canary strings — into Slack; paper titles,
abstracts, and your own relevance notes are fine.

## Write state back

Commit the writeup + ledger (+ `queries.md` on the first run) and ship through
the merge gate below. End with a ≤4-line status.

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
