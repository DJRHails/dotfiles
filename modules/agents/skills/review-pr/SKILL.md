---
name: review-pr
description: Review an existing GitHub PR with parallel agents (pr-review-toolkit + Codex + Gemini), post inline findings, fix them, run the quality pipeline, push, resolve threads, and post a summary. Right-sizes small / delta PRs to a direct single-pass review with no sub-agents. Use when asked to review and fix a PR, do a thorough multi-agent PR review, or run the review-pr flow on a PR number.
argument-hint: <pr-number>
---

# Review and Fix PR

Adapted from [trailofbits/claude-code-config](https://github.com/trailofbits/claude-code-config).

`$ARGUMENTS` is the GitHub PR number to review and fix (e.g. `/review-pr 42`).
If invoked without one, ask which PR before proceeding.

Read PR #$ARGUMENTS thoroughly using `gh pr view`. Understand the
full context: description, linked issues, commit history, and the
diff against the base branch.

Detect the upstream repository: if a git remote named `upstream`
exists, use it as the canonical repo. Otherwise, fall back to
`origin`. Resolve the canonical repo's `owner/name` (e.g. from
`git remote get-url upstream`) and store it — use
`--repo <owner/name>` on every `gh` command to ensure they target
the correct repository. Run `git fetch <upstream-remote>` to
ensure you are working with up-to-date code.

Check out the PR branch locally.

**Shared-repo guard:** determine whether the canonical repo is a
solo personal repo — owned by `github.com/DJRHails` with no other
collaborators. Concretely: solo means the owner is DJRHails and `gh api repos/<owner>/<repo>/collaborators --jq length` returns 1. On solo personal repos, run fully autonomously. On
any other repo (a shared org, or any repo with other
collaborators), pause before each action that reaches other people
— inline review comments (§1), thread replies and resolves (§4),
and the summary comment (§5) — post a short summary of what you
are about to send, and wait for explicit user confirmation.

Execute every step below sequentially without pausing for
confirmation, except where the shared-repo guard requires it.

## 0. Right-size the review (do this first)

Not every PR earns the full seven-agent battery. The fan-out in §1 (five
toolkit agents + Codex + Gemini, each up to a 10-minute timeout) exists for
substantial PRs; running it on a four-line fix or a docs tweak burns minutes
and tokens for no extra signal. Classify the PR first and pick the lane.

Measure the diff against the base (or, for a re-review, against the
last-reviewed commit — see **Delta re-reviews** below):

```bash
git diff --stat <upstream-remote>/<base-branch>...HEAD
git diff --name-only <upstream-remote>/<base-branch>...HEAD
```

**Lane A — direct review, NO sub-agents.** Take this lane when ANY holds:

- **Small:** roughly ≤ 80 changed lines across ≤ 5 hand-written files.
- **Low-risk types only:** the diff touches only docs/markdown, comments,
  config, fixtures, lockfiles, or generated files — no source logic.
- **Follow-up delta:** a "resolve review findings"-style PR layered on a
  parent already reviewed through this skill, where the new changes are
  themselves small — the parent's battery already covered the substance.

In Lane A, **skip §1's Pass A and Pass B entirely** — launch no Task agents
and do not call Codex/Gemini. Instead review the diff yourself in a single
pass: read every changed hunk and judge it against the repo's
CLAUDE.md/AGENTS.md conventions, looking for the same things the agents would
(correctness bugs, silent failures, test gaps, comment rot, type/invariant
issues). Rank findings P1–P4 and post the P1–P3 ones as inline comments
exactly as §1's "Post inline review comments" describes, then continue with
§2–§5 unchanged (fix → verify → push → resolve → summary).

**Lane B — full multi-agent review.** Real source changes beyond the Lane-A
thresholds. Run §1 as written.

**Borderline** (e.g. ~100 lines of straightforward source): prefer Lane A but
keep the single heaviest external opinion — run *one* of Codex or Gemini
(whichever is installed) as a sanity check and skip the five toolkit
sub-agents. When trimming the fan-out, drop the external CLIs first: they are
the slowest, most expensive part.

**Delta re-reviews.** When re-running this flow on a PR you already reviewed
that has since gained commits, review only the *new* delta — diff against the
previously-reviewed head (`git diff <last-reviewed-sha>...HEAD`), not the whole
PR — and reuse the existing inline threads (match on the `finding:F<n>`
tokens) instead of re-posting the full set. A small delta takes Lane A even if
the original PR was Lane B.

State which lane you picked and why in one line before proceeding.

## 1. Review

> Lane B (substantial PRs). For small / delta PRs, §0 replaces this whole
> section with a direct single-pass review — skip straight to §2.

Run two review passes in parallel, then merge findings.

### Pass A — pr-review-toolkit agents

Launch these Task tool agents **in parallel** (single message,
multiple tool calls), each with the matching `subagent_type` below
(vendored pr-review-toolkit agents). Tell each agent which files
changed (from `git diff --name-only <base>...HEAD`):

| agent | focus |
|-------|-------|
| `code-reviewer` | Code quality, style, project guidelines |
| `silent-failure-hunter` | Silent failures, swallowed errors, bad fallbacks |
| `pr-test-analyzer` | Test coverage gaps and missing edge cases |
| `comment-analyzer` | Comment accuracy, comment rot, doc completeness |
| `type-design-analyzer` | Type encapsulation, invariants, design quality |

(`code-simplifier` is the sixth toolkit agent — it mutates code rather
than reporting findings, so it runs as a polish step after fixes, not
in this read-only pass. See step 2.)

### Pass B — external second opinion

Launch these Task tool agents **in parallel with Pass A** — all
7 agents in a single message, multiple tool calls. Each uses
`subagent_type: general-purpose`.

**Codex reviewer** — tell the agent to run:

```bash
codex review --base <upstream-remote>/<base-branch> \
  -c model='"gpt-5.3-codex"' \
  -c model_reasoning_effort='"xhigh"'
```

- `--base` does not accept custom prompts (codex reads
  `AGENTS.md` at the repo root if one exists)
- If `gpt-5.3-codex` fails with an auth error, retry with
  `gpt-5.2-codex`
- Set `timeout: 600000` on the Bash call
- Tell the agent to summarize findings only — skip
  `[thinking]`/`[exec]` blocks and sandbox warnings
- If `codex` is not installed, report and skip

**Gemini reviewer** — tell the agent to run:

```bash
git diff <upstream-remote>/<base-branch>...HEAD > /tmp/pr-review-diff.txt

# Build prompt file (avoids heredoc shell expansion issues)
{
  echo "Review this diff for code quality, bugs, and improvements."
  if [ -f AGENTS.md ] || [ -f CLAUDE.md ] || [ -f .agents/AGENTS.md ] || [ -f .claude/CLAUDE.md ]; then
    echo ""
    echo "Project conventions:"
    echo "---"
    cat AGENTS.md CLAUDE.md .agents/AGENTS.md .claude/CLAUDE.md 2>/dev/null
    echo "---"
  fi
  echo ""
  echo "Diff:"
  cat /tmp/pr-review-diff.txt
} > /tmp/pr-review-prompt.txt

# Pipe prompt via stdin to avoid shell metacharacter issues
cat /tmp/pr-review-prompt.txt | gemini -p - \
  -m gemini-3-pro-preview \
  --yolo
```

- Uses stdin (`-p -`) instead of heredoc to avoid shell
  expansion issues with `$`, backticks, etc. in diffs
- Set `timeout: 600000` on the Bash call
- If `gemini` is not installed, report and skip

### Merge findings

Collect results from all 7 sources (5 toolkit agents + Codex +
Gemini). Deduplicate overlapping findings — if multiple sources
flag the same issue, keep the most specific description and note
the consensus. Rank every finding by severity:

- **P1** — blocks merge (correctness bugs, security issues)
- **P2** — important (missing error handling, test gaps, logic flaws)
- **P3** — nice to have (style, naming, minor simplifications)
- **P4** — informational (observations, suggestions for future work)

### Post inline review comments

Post every P1–P3 finding as an **inline review comment** anchored to
the file and line it concerns, so each issue becomes its own
resolvable thread on the PR. (P4 findings stay in the §5 summary
only.)

Capture the PR head commit (the inline comments anchor to it):

```bash
HEAD_SHA=$(gh pr view $ARGUMENTS --repo <owner/name> \
  --json headRefOid -q .headRefOid)
```

Build a single review payload so the comments post atomically. Give
every comment a hidden, stable token (`<!-- finding:F<n> -->`) so the
resolve step can match threads back to findings even after line
numbers shift. Write it to a file to avoid shell-escaping issues with
code in the bodies — `/tmp/pr-inline-review.json`:

```json
{
  "commit_id": "<HEAD_SHA>",
  "event": "COMMENT",
  "body": "Automated review — findings posted inline. Each thread is resolved as its fix lands.",
  "comments": [
    {
      "path": "src/foo.py",
      "line": 42,
      "side": "RIGHT",
      "body": "**P1 — correctness:** <description and suggested fix>\n\n<!-- finding:F1 -->"
    }
  ]
}
```

Then create the review:

```bash
gh api --method POST \
  repos/<owner>/<name>/pulls/$ARGUMENTS/reviews \
  --input /tmp/pr-inline-review.json
```

Rules:

- Only lines present in the `base...HEAD` diff can carry an inline
  comment. For a multi-line range add `start_line`/`start_side`. If a
  finding's line is **not** in the diff, drop it from the payload and
  record it for the §5 summary instead.
- Use `event: COMMENT` — you cannot request changes on a PR you are
  about to push to.
- Keep the `finding:F<n>` token in every body; the resolve step
  depends on it.

## 2. Fix findings

Address all P1–P3 findings. For each finding, either:

- **Fix it** — apply the change, or
- **Dismiss it** — explain why it's a false positive or not worth
  the churn (e.g. a stylistic disagreement or an impossible edge
  case). Document the reasoning inline.

When a fix requires external context — unfamiliar library behavior,
unclear API semantics, or an error you don't recognize — search
for solutions rather than guessing.

P4 findings are informational — note them but do not fix unless
trivial.

### Polish — code-simplifier

Once all findings are addressed, launch the
`code-simplifier` agent on the files changed by
this PR (and by your fixes). Apply only simplifications that
**preserve behavior** — clarity, readability, and project-standard
adherence. Skip any that alter functionality or conflict with a
deliberate decision in the PR; note those as P4 instead. This is
the toolkit's "after passing review" polish step.

After addressing all findings, review your own fixes: read the
diff of changes made in this step and verify each fix is correct,
doesn't introduce new issues, and doesn't regress other parts of
the PR. If you spot a problem, fix it before proceeding.

## 3. Verify

### 3a. Discover project checks (CI is the source of truth)

Before running anything, read the project's CI configuration to
learn what the project *actually* runs. This takes priority over
the fallback tables below.

1. **Read CI workflows.** Scan `.github/workflows/` for the main
   CI workflow (typically `ci.yml`, `test.yml`, or `build.yml`).
   Extract:
   - Test commands with feature flags (e.g.
     `cargo test --features foo,bar`)
   - Lint/format commands with non-default flags
   - Any step that runs a command then checks `git diff --exit-code`
     — these are **codegen sync checks** (schema generation,
     snapshot updates, help text, etc.). Record the command.
   - Docs/site build commands (e.g. `make site`, `mkdocs build`)
2. **Read the Makefile** (if present). Cross-reference targets
   used in CI — these are the ones that matter.
3. **Read AGENTS.md or CLAUDE.md** (if present at repo root or `.agents/`/`.claude/`).
   It may define project-specific quality gates.

Store the discovered commands. They override the fallback table
for any overlapping step.

### 3b. Run the quality pipeline

Detect the project language from manifest files (`Cargo.toml` →
Rust, `pyproject.toml`/`setup.py` → Python, `package.json` →
Node/TypeScript, `go.mod` → Go). A project may use multiple
languages; run checks for each.

Run checks in this order. For each step, use the CI-discovered
command if one was found; otherwise fall back to the default.

1. **Build** — compile or bundle
2. **Test** — run the full test suite with the same feature flags
   CI uses. Iterate on failures until green.
3. **Lint and format** — fix any issues
4. **Extended checks** — per-language extras (see fallback table)
5. **Codegen sync** — for every codegen check discovered in 3a,
   run the command and verify `git diff --exit-code`. If the diff
   is non-empty, the generated files are stale — regenerate and
   stage them.
6. **Docs build** — if the PR changes documentation files and a
   docs build command exists, run it to verify the docs compile.

### Fallback defaults (when CI config is absent or unclear)

**Rust** (detected by `Cargo.toml`):

| step         | command                                        |
|--------------|------------------------------------------------|
| build        | `cargo build`                                  |
| test         | `cargo test`                                   |
| lint         | `cargo clippy -- --deny warnings`              |
| format       | `cargo fmt --check`                            |
| supply chain | `cargo deny check` (if `deny.toml` exists)    |
| careful      | `cargo careful test` (if `cargo-careful` installed) |

**Python** (detected by `pyproject.toml` or `setup.py`):

| step         | command                                        |
|--------------|------------------------------------------------|
| test         | `pytest -q`                                    |
| lint         | `ruff check`                                   |
| format       | `ruff format --check`                          |
| types        | `ty check` (or `mypy` if configured)           |
| supply chain | `pip-audit`                                    |

**Node/TypeScript** (detected by `package.json`):

| step         | command                                        |
|--------------|------------------------------------------------|
| build        | per project (`npm run build`, `tsc`, etc.)     |
| test         | `vitest` (or project test script)              |
| lint         | `oxlint` (or project lint script)              |
| format       | `oxfmt --check` (or project format script)     |
| types        | `tsc --noEmit`                                 |
| supply chain | `pnpm audit --audit-level=moderate`            |

**Go** (detected by `go.mod`):

| step         | command                                        |
|--------------|------------------------------------------------|
| build        | `go build ./...`                               |
| test         | `go test ./...`                                |
| lint         | `golangci-lint run`                            |
| format       | `gofmt -l .`                                   |
| vet          | `go vet ./...`                                 |

If a tool is not installed, skip it with a note rather than
failing the pipeline.

## 4. Commit and push

- Commit the fixes as a separate commit (do not squash into the
  original — preserve review history)
- Write a detailed commit message that covers:
  - Subject: `fix: resolve code review findings for PR #$ARGUMENTS`
  - Body: list findings by severity, what was fixed vs dismissed
    (with brief reasoning), and confirmation that the quality
    pipeline passes
- Push the branch (regular push, not force-push)

### Resolve fixed comment threads

After the fixes are pushed, close the loop on every inline thread
from §1. Fetch the threads and their hidden tokens with `gh`:

```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100){ nodes{
          id isResolved
          comments(first:1){ nodes{ databaseId body } }
        }}
      }
    }
  }' -f owner=<owner> -f repo=<name> -F pr=$ARGUMENTS
```

For each thread, read the `<!-- finding:F<n> -->` token from its first
comment and look up that finding's disposition:

- **Fixed** — reply with the fix commit, then resolve the thread:

  ```bash
  gh api --method POST \
    repos/<owner>/<name>/pulls/$ARGUMENTS/comments \
    -f body='Fixed in <commit-sha>.' -F in_reply_to=<databaseId>

  gh api graphql -f query='
    mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){
      thread{ id isResolved } } }' -f id=<thread-node-id>
  ```

- **Dismissed (false positive)** — reply with the reasoning but leave
  the thread **open** for the author to adjudicate. Only fixes
  auto-resolve.

Leave threads with no `finding:` token untouched — they are not ours.

## 5. PR comment

Post a review summary as a PR comment using
`gh pr comment $ARGUMENTS --repo <owner/name>`.

Format the comment body as:

```
## Review Summary

### Findings

[For each severity level that has findings, list them as a table:]

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| 1 | P1 | [description] | Fixed: [what was done] |
| 2 | P2 | [description] | Dismissed: [reasoning] |
| ... | ... | ... | ... |

### Verification

- **Tests**: [pass/fail count]
- **Lint**: [clean/issues]
- **Format**: [clean/issues]

### Commit

[commit SHA and subject line]
```
