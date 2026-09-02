---
name: review-pr
description: Review an existing GitHub PR — one verified single-pass read of the diff, inline P1–P3 findings, fixes for the P1/P2s pushed to the PR branch, scoped verification, resolved threads, a summary. Escalates to a two-reader second opinion only for large source changes. Use when asked to review and fix a PR, or to run the review-pr flow on a PR number.
argument-hint: <pr-number>
---

# Review and Fix PR

`$ARGUMENTS` is the PR number (e.g. `/review-pr 42`). Without one, ask which PR.

Every finding must be **verified** before it is posted (a code path you read or
ran), and P1/P2 findings are **fixed** on the PR branch. Those two properties
are the product. Everything else in this file is about doing them in as few
API requests and as little context as possible: a review's cost is the number
of requests times the context each one re-reads, so the rules below are shaped
as *mechanisms* (what to run, what to read, what to keep out of the transcript),
not exhortations.

## Ground rules

- **Canonical repo.** `upstream` remote if present, else `origin`; pass
  `--repo <owner/name>` on every `gh` call.
- **Shared-repo guard.** Solo repo = owner `DJRHails` and
  `gh api repos/<owner>/<repo>/collaborators --jq length` returns 1: act
  autonomously. Any other repo: summarise what you are about to post/push and
  wait for an explicit yes before each action that reaches other people
  (§3 review, §4 push/resolve, §5 summary). As a gantry worker the spawn is
  the authorization — never block.
- **Gantry sign-off.** When `$GANTRY_URL` is set, end **every** body you post
  (review body, each inline comment, each thread reply, the summary) with
  `_[via gantry](<GANTRY_URL>)_` as its last line. It is the loop guard
  portcullis keys on to drop your own posts when they echo back as webhooks —
  an unsigned reply re-triggers your own run (touchstone#2290: 11 unsigned
  replies, 11 phantom re-reviews).
- **Context discipline** (these bound cost without touching what you review):
  - One message per *batch* of independent calls: metadata + diff stat +
    file list + collaborator count is one message, not five.
  - Read the diff once, from disk. Read files by **line range around the
    hunks** (`sed -n 'a,bp'`), not `cat` of whole files; a whole-file read
    only for files under ~300 lines.
  - Every command that can print more than ~150 lines writes to a file
    (`> /tmp/review/<name>.log 2>&1`) and you read a `tail -40` / `rg`
    of it — never the whole output into the transcript.
  - Keep any single tool call under ~4 minutes (`timeout 240`, or run in the
    background and poll at ≤4-minute intervals): the 5-minute prompt cache
    expires across a longer gap and the next request re-writes the entire
    context at write rates.
  - Narration between calls: one line when a decision needs recording.

## 1. Orient (one message)

```bash
gh pr view $ARGUMENTS --repo <owner/name> --json title,body,baseRefName,headRefOid,commits,additions,deletions,files
git fetch <remote> <base> -q && git diff --stat <remote>/<base>...HEAD && git diff --name-only <remote>/<base>...HEAD
gh api repos/<owner>/<repo>/collaborators --jq length
```

Then write the diff once: `git diff <remote>/<base>...HEAD > /tmp/review/pr.diff`
and read it (in ≤3 chunks if it exceeds ~1,500 lines). Check out the PR
branch if not already on it.

**Re-entry (a later turn on a PR you already reviewed):** run exactly one
command first — `gh pr view $ARGUMENTS --json headRefOid -q .headRefOid` —
and compare with the fix commit you pushed (recorded in your summary
comment). Equal → this is your own push echoing back: end the turn with one
line, no re-review, no posts. Otherwise review only the delta
(`git diff <last-reviewed-sha>...HEAD`) and reuse the existing threads via
their `finding:F<n>` tokens. If this session did not do the earlier review,
recover both from GitHub: the newest review whose body starts
"Automated review" gives `commit_id` (the last-reviewed SHA), and the PR's
review threads give the findings.

## 2. Review (single verified pass)

Read every hunk once against the repo's CLAUDE.md/AGENTS.md and judge it
through all five lenses — this pass replaces a five-agent fan-out, so walk
them deliberately per hunk rather than reading for a general impression:

1. **Correctness** — wrong logic, broken invariants, off-by-ones, races,
   unhandled states; **callers and adjacent writers** of anything whose
   contract changed (`rg` the symbol — a live sibling that still assumes the
   old contract is a P1, and it is never in the diff).
2. **Silent failures** — swallowed exceptions, fail-open fallbacks, defaults
   that mask a missing value, logging that stands in for raising.
3. **Tests** — does a test pin each claimed behaviour, and would a plausible
   regression fail it? Stubs that discard their arguments, assertions on
   shape but not value.
4. **Claims vs reality** — comments, docstrings, docs, and PR description
   claims (especially numbers) that the code or data does not bear out.
   Re-measure a quantitative claim when the data is at hand.
5. **Types and invariants** — states representable that should not be,
   flags where an enum belongs, validation that lives in a docstring.

Verify each candidate before it becomes a finding: read the code path, run
the command, or reproduce the number. Chase a bug class across the PR's
changed surface once (`rg` for siblings) and post the class as one finding.
Reject speculative "what if the caller does X" risks and rewrites.

Rank: **P1** blocks merge (correctness, security, data loss); **P2**
important (missing error handling, test gaps, logic flaws, false claims);
**P3** nice-to-have (style, naming, small simplifications); **P4**
observations — summary only. Two calibration rules the shadow runs of this
procedure got wrong against the reviews they were scored on: a **test gap is
P2** whenever a plausible regression would pass the suite (a stub that
discards its arguments, an assertion on shape but not value, an error path
no test exercises) — not a P3 because the code happens to be right today;
and a **documented contract the code cannot deliver** (a promised error
that no input reaches, a docstring guarantee the fail-soft path breaks) is
P2, not a comment nit. 3–5 well-chosen findings beat 30 nits.

**Second opinion — large source changes only.** When the diff changes more
than ~400 lines of hand-written source (tests, docs, generated files and
lockfiles excluded), launch `code-reviewer` and `silent-failure-hunter` in
one message, in parallel, with a prompt carrying: the repo path, the base
ref, the path of `/tmp/review/pr.diff`, the changed-file list, the PR's gist,
and the instruction to report **only P1/P2 candidates** as `path:line — claim
— how to verify` in ≤300 words written to `/tmp/review/<agent>.md`,
returning just that path. Verify their candidates yourself like your own.
Everything smaller is a direct review with no sub-agents.

## 3. Post the inline review (one message)

Build one review payload so the comments post atomically. Each comment
carries a hidden token so §4 can match threads after lines shift:

```json
{"commit_id": "<HEAD_SHA>", "event": "COMMENT",
 "body": "Automated review — findings posted inline. P1/P2 threads resolve as their fixes land; P3s are left for the author.",
 "comments": [{"path": "src/foo.py", "line": 42, "side": "RIGHT",
   "body": "**P1 — correctness:** <what breaks, evidence, suggested fix>\n\n<!-- finding:F1 -->"}]}
```

Write it to `/tmp/review/inline.json` and
`gh api --method POST repos/<owner>/<repo>/pulls/$ARGUMENTS/reviews --input /tmp/review/inline.json`.

- Only lines in the `base...HEAD` diff can carry a comment
  (`start_line`/`start_side` for ranges); a finding elsewhere goes to the §5
  summary instead.
- `event: COMMENT` — you cannot request changes on a PR you will push to.
- Sign-off after the token in each body and at the end of the review body.

## 4. Fix P1/P2, verify, push, resolve

Fix every P1 and P2 with the smallest change at the correct ownership
boundary; a finding you decide is a false positive gets a reply explaining
why and stays open. **P3s are posted, not fixed** — they are the author's
call (fix one only when it is a one-line change in a file you are already
editing). No polish pass.

Verify what your fixes touch, not the world:

- the tests that cover the changed files (plus any test you wrote), the
  project's lint/format/type checks **on the changed files**, and any
  codegen-sync check CI runs whose inputs you touched (read
  `.github/workflows/` once to learn the commands; CLAUDE.md may name
  quality gates);
- the full suite only when the repo has no CI covering it — otherwise the
  PR's own CI on your pushed head is the backstop, and a red check comes back
  to you as a follow-up turn;
- a toolchain that never installed (a failed `uv sync`, mass
  `unresolved-import`) is a void result, not evidence: repair it or say you
  could not verify — never post its output as findings.

Commit the fixes as **one** separate commit (never amend or squash the
author's): subject `fix: resolve code review findings for PR #$ARGUMENTS`,
body listing each finding as fixed/dismissed with one line of reasoning.
Regular push to the PR head branch — never to main, never force.

Then close the loop in **one script**: fetch the threads, and for each
`finding:F<n>` token you own, reply `Fixed in <sha>.` and resolve the thread
(fixed), or reply with the reasoning and leave it open (dismissed / P3).

```bash
gh api graphql -f query='query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){
  reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{databaseId body}}}}}}}' -f o=<owner> -f r=<repo> -F p=$ARGUMENTS
gh api --method POST repos/<owner>/<repo>/pulls/$ARGUMENTS/comments -f body='Fixed in <sha>.

_[via gantry](<GANTRY_URL>)_' -F in_reply_to=<databaseId>
gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id=<threadId>
```

Threads without a `finding:` token are not yours — leave them.

## 5. Summary comment

`gh pr comment $ARGUMENTS --repo <owner/name> --body-file /tmp/review/summary.md`:

```
## Review Summary

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| F1 | P1 | … | Fixed in <sha> |
| F2 | P3 | … | Left for the author |

**Verified:** <exactly what ran — tests, lint, types — and what was deferred to CI>
**Fix commit:** <sha> (or "none pushed")
```

Name what you could not verify. If your agent contract requires a
`Verdict:` line, it goes after the table and before the sign-off.
