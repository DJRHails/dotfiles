# Global Development Standards

Global instructions for all projects. Project-specific AGENTS.md (or CLAUDE.md) files override these defaults.

## Philosophy

- **No speculative features** - Don't add features, flags, or configuration unless users actively need them
- **No premature abstraction** - Don't create utilities until you've written the same code three times
- **Clarity over cleverness** - Prefer explicit, readable code over dense one-liners
- **Name things for what they are** - Give every coined identifier a short descriptive name, never an opaque label or sequence number: `direct-review` not `lane A`, "the premise-check phase" not "Phase 1", "the seam gate" not `G3`. This covers code (enum variants, functions, flags), plan phases, doc sections and headings, review-finding IDs, figures and tables, file names — anywhere a name accretes. Numbers and bare letters rot: inserting or reordering one entry renumbers the rest and silently breaks every cross-reference, and the label carries no meaning, where a descriptive name is self-documenting and a stable anchor. Exceptions: intrinsic ordinals (fixed pipeline stages, list positions, weeks, ladder rungs) and external identifiers quoted verbatim (another paper's `Fig 4a`, a dataset's category code).
- **Justify new dependencies** - Each dependency is attack surface and maintenance burden
- **Replace, don't deprecate** - When a new implementation replaces an old one, remove the old one entirely. No backward-compatible shims, dual config formats, or migration paths. Proactively flag dead code. **A "graceful degradation" path for stale data or an old schema version IS a deprecation shim** — and the specific danger is that it hides *total* failures: a reader (or a UI) that silently omits a section cannot distinguish "this never shipped" from "not applicable here". One night, two separate produce-side bugs (no report ever shipped an export node; 0 of 46 carried a task node) stayed invisible for hours behind a null-on-unknown-schema reader that had four tests pinning the degradation as intended. Prefer: **hard-fail on version drift, naming expected vs found; regenerate the data to the current version; and keep a clearly *explained* absence only where the thing is genuinely inapplicable by construction.** Order matters — regenerate first, then flip to failing, or every stale record 500s.
- **Verify at every level** - Set up automated guardrails (linters, type checkers, pre-commit hooks, tests) as the first step, not an afterthought. Prefer structure-aware tools (ast-grep, LSPs, compilers) over text pattern matching.
- **Edit files with the `edit` tool, never a scripted find-and-replace** - Reach for `edit` (exact-match replacement) for every targeted change. Do NOT shell out to `python3 - <<'PY' … p.write_text(t)`, `sed -i`, `perl -pi`, or any other write-the-whole-file script to make an edit. Two reasons, and the second is the dangerous one: (1) a scripted replace is invisible in review — `edit` shows the before/after, a heredoc shows a wall of code; (2) **`str.replace` and `sed` silently no-op when the pattern doesn't match and still write the file**, so a stale or mis-typed pattern produces a confident "patched" with nothing changed, while `edit` fails loudly on a miss or a non-unique match. That failure mode is worst exactly where the stakes are highest — resolving merge conflicts, threading a renamed symbol, fixing an import after a refactor — because the whole risk *is* the pattern not matching what you assumed. Batch multiple changes to one file as several `edits[]` entries in a single call. Narrow exceptions, all of which must be stated out loud: a genuinely mechanical sweep across many files (`sed -i 's/old_import/new_import/g' $(rg -l …)`), and regex over unpredictable generated text (stripping conflict markers). Even then, verify with a type check or test afterwards — never assume the sweep landed. Two concrete ways a blanket `str.replace` bites during a rename, both observed: (1) **it rewrites the text that explains the old name** — a docstring or writeup section documenting "we used to call this X" silently becomes self-contradictory; (2) **it double-substitutes when the new name contains the old one** (`CLEAN_STRATA` → `CASCADE_CLEAN_STRATA` applied twice yields `CASCADE_CASCADE_CLEAN_STRATA`). After any rename sweep, grep for the old name expecting only the deliberate historical mentions, and grep for the doubled form.
- **Bias toward action** - Decide and move for anything easily reversed; state your assumption so the reasoning is visible. Ask before committing to interfaces, data models, architecture, or destructive operations. When given a bug report, just fix it — don't ask for hand-holding. Point at logs, errors, failing tests, then resolve them. Zero context switching required from the user.
- **Confirm before contacting other humans** - Any action that delivers a message to someone other than me — sending email, posting Slack into a channel/DM with anyone else in it, creating or updating a calendar event with attendees (or `--send-updates` anything other than `none`), opening/commenting/merging GitHub PRs and issues, posting to Linear/Notion/Jira where teammates are notified, or any webhook/API call that reaches a person — requires you to first post a short summary (recipients, subject/title, body, timing) and then wait for my explicit "yes" / "send it" / "go ahead". My initial request ("send the invite to X", "reply to this email", "message Alice") is the trigger, not the authorization. Drafts and local-only artifacts that don't notify anyone are exempt. **Exempt: GitHub PRs and issues on my own personal repos (**`github.com/DJRHails/`***) — open, comment, and merge them freely without a confirmation step, since they're solo repos that notify no one else.** The confirmation step still applies to repos in shared orgs (e.g. `safety-research`) or any repo with other collaborators. **Also exempt: the** `hails-talk` **Slack workspace (**`hails-talk.slack.com`**, team** `Hails`**) is solo — only me and my own bots (e.g.** `sage_saint`**) — so post / reply / edit / react there freely without confirmation, including with** `--yes`**. This is the slack skill in bot mode via** `$SLACK_BOT_TOKEN` **(sourced from the touchstone** `.env`**; that token is scoped to this one workspace).** Any OTHER Slack workspace (Anthropic / fellows Enterprise Grid, etc.) still requires the summary + explicit confirmation.
- **Sign every GitHub post you make through my token** - My personal repos (`github.com/DJRHails/*`) have portcullis webhooks: an issue/PR comment from the `DJRHails` account is read as a maintainer request and **spawns a gantry worker to act on it**. You post through my token, so your posts look like mine — the only mark portcullis's loop guard can key on is a trailing attribution footer. End every PR/issue comment, review, and PR description you post on my repos with `_[via <who>](<link>)_` as the last line — `<who>` names the agent/session (`claude @ taffy`, `sage`, …), `<link>` is any relevant URL (the session, the repo, hails.info). Unsigned agent posts have spawned phantom workers on already-merged PRs (touchstone#2856, 2026-08-05): each completion report without the footer burned a fresh worker that had to no-op. This is a loop guard, not vanity — a human request (mine) is exactly a post *without* the footer, so never add it to text I typed and asked you to relay verbatim.
- **Finish the job** - Handle the edge cases you can see. Clean up what you touched. If something is broken adjacent to your change, flag it. But don't invent new scope.
- **Falsify, first** - When I report a bug, don't start by trying to fix it. Instead, start by writing a test that reproduces the bug. Then, have subagents try to fix the bug and prove it with a passing test.
- **Prove it works** - Never mark a task complete without demonstrating correctness. Run tests, check logs, diff behavior. Ask: "Would a staff engineer approve this?"
- **An incidental number is not a measurement — check its N and whether it was the study's object.** A figure produced as a *by-product* of work aimed at something else has had none of the care the headline numbers got: no replication, no seed averaging, often a single draw and a tiny N. Before promoting one to a claim (let alone into a brief that spends hours of compute), ask what it was measuring, how many observations it rests on, and whether anything controlled it. One night I took a three-case, single-seed by-product from a plumbing PR, labelled it "the largest uncontrolled instrument artifact in the family", said it "dwarfs" a decision the team had just spent hours making, and filed it as a priority. Measured properly it was **a quarter** the size of the artifact it supposedly displaced, sign-flipped between models, and sat inside the instrument's own grid step — the original reading was one draw from a distribution spanning 35–60. Corollary for summarising other people's work: when you restate a lane's finding, restate the number it *registered*, not the striking one it mentioned in passing.



## Code Quality



### Hard limits

1. ≤100 lines/function, cyclomatic complexity ≤8
2. ≤5 positional params
3. 100-char line length
4. Absolute imports only — no relative (`..`) paths
5. Google-style docstrings on non-trivial public APIs



### Regex convention

All regex patterns must use verbose (`x`) mode via multi-line raw strings. Include inline comments for each component:

```python
_PATTERN = re.compile(
    r"""(?ix)        # case-insensitive, verbose
    \b               # word boundary
    (?:foo | bar)    # match foo or bar
    \b               # word boundary
    """
)
```

Never use compact single-line regex for anything beyond trivial patterns. Prefer named groups (`(?P<name>...)`) over numbered groups for any capturing group.

### Array & DataFrame typing

Use `jaxtyping` for shape/dtype annotations on numpy arrays. No JAX dependency required — it supports numpy, torch, etc.:

```python
from jaxtyping import Float, Int
import numpy as np

def normalize(x: Float[np.ndarray, "batch features"]) -> Float[np.ndarray, "batch features"]:
    ...
```



### Zero warnings policy

Fix every warning from every tool — linters, type checkers, compilers, tests. If a warning truly can't be fixed, add an inline ignore with a justification comment. Never leave warnings unaddressed.

### Comments

Code should be self-documenting. No commented-out code—delete it. If you need a comment to explain WHAT the code does, refactor the code instead.

### Error handling

- Fail fast with clear, actionable messages
- Never swallow exceptions silently
- Include context (what operation, what input, suggested fix)



### Testing

- **Test behavior, not implementation.** If a refactor breaks your tests but not your code, the tests were wrong.
- **Test edges and errors, not just the happy path.** Empty inputs, boundaries, malformed data, missing files, network failures.
- **Mock boundaries, not logic.** Only mock things that are slow, non-deterministic, or external services you don't control.
- **Verify tests catch failures.** Break the code, confirm the test fails, then fix.



## Development

When adding dependencies, CI actions, or tool versions, always look up the current stable version — never assume from memory.

### CLI tools


| tool           | replaces   | usage                                                                      |
| -------------- | ---------- | -------------------------------------------------------------------------- |
| `rg` (ripgrep) | grep       | `rg "pattern"` - fast regex search                                         |
| `fd`           | find       | `fd "*.py"` - fast file finder                                             |
| `ast-grep`     | -          | `ast-grep --pattern '$FUNC($$$)' --lang py` - AST-based code search        |
| `shellcheck`   | -          | `shellcheck script.sh` - shell script linter                               |
| `shfmt`        | -          | `shfmt -i 2 -w script.sh` - shell formatter                                |
| `actionlint`   | -          | `actionlint .github/workflows/` - GitHub Actions linter                    |
| `zizmor`       | -          | `zizmor .github/workflows/` - Actions security audit                       |
| `prek`         | pre-commit | `prek run` - fast git hooks (Rust, no Python)                              |
| `trash`        | rm         | `trash file` - moves to the OS trash (recoverable). **Never use** `rm -rf` |


Prefer `ast-grep` over ripgrep when searching for code structure (function calls, class definitions, imports). Use ripgrep for literal strings and log messages.

### Python

**Runtime:** 3.13 with `uv venv`


| purpose       | tool                         |
| ------------- | ---------------------------- |
| deps & venv   | `uv`                         |
| lint & format | `ruff check` / `ruff format` |
| static types  | `ty check`                   |
| tests         | `pytest -q`                  |


**Always use uv, ruff, and ty** over pip/poetry, black/pylint/flake8, and mypy/pyright. Supply chain: `pip-audit` before deploying, pin exact versions (`==` not `>=`) with `uv pip install --require-hashes`.

**IDs:** Prefer UUIDv7 for primary keys. Expose prefixed Base62 IDs in APIs (`usr_...`, `thrd_...`), not raw UUIDs.

### Node/TypeScript

**Runtime:** Node 22 LTS, ESM only (`"type": "module"`)


| purpose | tool           |
| ------- | -------------- |
| lint    | `oxlint`       |
| format  | `oxfmt`        |
| test    | `vitest`       |
| types   | `tsc --noEmit` |


Supply chain: `pnpm audit --audit-level=moderate` before installing, pin exact versions (no `^` or `~`).

### Rust

**Runtime:** Latest stable via `rustup`


| purpose      | tool                                                       |
| ------------ | ---------------------------------------------------------- |
| build & deps | `cargo`                                                    |
| lint         | `cargo clippy --all-targets --all-features -- -D warnings` |
| format       | `cargo fmt`                                                |
| test         | `cargo test`                                               |
| supply chain | `cargo deny check`                                         |
| safety check | `cargo careful test`                                       |


**Style:** Prefer `for` loops with mutable accumulators over iterator chains. Use `let...else` for early returns. No wildcard matches.

**Type design:** Newtypes over primitives. Enums for state machines, not boolean flags. `thiserror` for libraries, `anyhow` for applications. `tracing` for logging.

### Bash

All scripts must start with `set -euo pipefail`. Lint: `shellcheck script.sh && shfmt -d script.sh`

### GitHub Actions

Pin actions to version tags: `actions/checkout@v4` (use `persist-credentials: false`). Scan workflows with `zizmor` before committing.

### Docker

- Always check existing `.env` files before asking the user for env vars
- Running containers don't pick up `.env` changes — recreate containers (`docker compose up -d`), don't just restart them



## Workflow



### Subagent strategy

- Use subagents liberally to keep the main context window clean
- Offload research, exploration, and parallel analysis to subagents
- One tack per subagent for focused execution
- For complex problems, throw more compute at it via subagents
- **On stall, always cancel and restart — proactively, don't wait for the user.** The harness
  pings the parent when an autonomous subagent stalls; treat that ping as an action item, not a
  notification. Immediately: (1) check whether it committed/pushed anything salvageable (branch,
  worktree, PR) so you don't lose or duplicate work; (2) cancel/kill it; (3) re-spawn with the
  same task (fresh spawn if it left no trace, else resume its session). A stalled agent never
  self-recovers — every minute you wait for it is wasted. Never leave a stalled subagent sitting.
- **Check the installed package commit BEFORE re-spawning a stalled agent, not after.** The rule
  below says a stall is usually a stale package; act on it first. Three consecutive stalls were
  burned one night before checking, and the clone was 12 commits behind origin. One `git log -1`
  costs seconds; three re-spawns cost twenty minutes.
- **Resume is far less reliable than a fresh spawn — try it once, then stop.** A resumed session
  that exits instantly (code 143, no output) will do so every time; the failure is in the resume
  path, not the task. Re-spawn fresh with a **self-contained** brief instead. Corollary: handing
  follow-up work to a finished lane costs a full re-brief, so put everything a lane needs in its
  original brief where you can.
- **Spawn failures and your own turn failures are different queues.** If spawns die instantly on
  provider overload while your own tool calls flow normally, stop retrying and **do the work
  in-process**. Four spawn attempts died in a row one night while the main session was healthy;
  the fix was to stop spawning, not to wait longer.
- **Before spawning, check the task is not already done.** On a fast-moving repo with parallel
  sessions, grep the merged PRs (`gh pr list --state merged --search <topic>`, or the docs the
  work would touch) for the task first. A second-monitor replication was one call from being
  duplicated after another session had already merged it hours earlier.
- **No report does NOT mean no work — check the branch before re-spawning.** Two lanes in one
  session opened PRs, got them **merged**, and then died without ever signalling completion; the
  only way I found out was auditing `git branch -r` and `gh pr list --head <branch>`. Re-spawning
  on the assumption of failure would have duplicated finished, merged work. When a lane goes
  quiet: check its branch, its PR state, and its worktree **first**.
- **`subagent_interrupt` is not termination.** It sends Escape; the pane, session and watcher stay
  alive, and the harness will eventually report the lane as failed with exit 143. If you are done
  with a lane, kill its process group (`kill -TERM -- -<pid>`, found via the
  `sessions/*/artifacts/*.sh` wrapper) rather than leaving idle panes to accumulate.

### Pi-specific configuration

- **Spawn subagents on the** `anthropic-api` **provider (the configured default); pick the model to
fit the task — no Opus pin.** `anthropic-api` uses the load-balanced `ANTHROPIC_API_KEY_`* keys
and works wherever they resolve. **Any registered** `anthropic-api` **model works, including non-Opus
(**`claude-fable-5`**,** `claude-haiku-4-5`**,** `claude-sonnet-5`**)** — use a cheap/small model for recon,
reviews, and parallel fan-out; reserve `claude-opus-5[fast]` for work that needs the frontier.
The old "always pin to `claude-opus-4-8[fast]`" rule was a *workaround* for two real bugs in
`DJRHails/pi-interactive-subagents`, **both fixed and on** `main` **since 2026-07-24**: a
bare/ambiguous model id (e.g. `claude-fable-5`) fell through to pi's keyless built-in `anthropic`
provider and the subagent "stalled and exited with no output" on hosts like `taffy` — fixed by
reading the parent provider from `ctx.model` (not the nonexistent `ctx.getModel()`) so bare ids
route to the parent's provider (patch #9) — plus recovering the zellij `new-pane` id by pane-diff
so parallel/crowded-tab spawns don't orphan panes (patch #12). **This is about the agent-harness
*subagent spawn* only — it does NOT relax any project's monitor/eval sweep rule (frontier
monitors, Sonnet-and-above with an Opus arm), which lives in that project's CLAUDE.md.**
- **A stalled/no-output subagent is almost always a STALE INSTALLED PACKAGE, not a model or
provider fault. Check the installed code's commit before theorising.** `pi` installs git packages
as plain clones under `~/.pi/agent/git/<host>/<owner>/<repo>` — a *separate* clone from any
`$PROJECTS` checkout, and nothing re-pulls it after the initial install. On 2026-07-25 that clone
sat 10 days stale at an old commit while the fix had long since shipped, and the whole failure
looked like a provider/model bug. Diagnose with `git -C ~/.pi/agent/git/github.com/<owner>/<repo> log --oneline -1`; fix with `pi update <source>` (fetches + resets to `origin/HEAD`), then
**restart pi** — a running process has the old extension in memory. The daily dotfiles autoupdate
now refreshes these automatically (`modules/dotfiles-autoupdate/update.sh`).
- **In a patch-stack fork, an OPEN patch PR does not mean unintegrated — never use PR state as the
signal.** Repos managed by `DJRHails/patch-stack-action` (commits prefixed `patch-stack:`) keep
every `patch/*` PR open against `base` permanently; integration happens by force-rebuilding
`main` from `base` + all patches. So `gh pr list --state open` listing a fix means nothing. Check
`git log origin/main` (after `git fetch`, since `main` is force-pushed) for the actual state, and
**never** `gh pr merge` **a** `patch/`* **branch** — the next rebuild discards it. Also note `gh` resolves
to the *upstream* parent repo by default on a fork, silently answering about the wrong repo; pass
`--repo <owner>/<repo>` explicitly.
- **The mirror of that trap: a PUSHED** `patch/`* **branch is not integrated either.** Both directions
bite, and `git log origin/main` is the only signal for either. Having pushed a cmux fix to
`patch/cmux-stale-surface` (2026-07-29), I told the user a pi restart would pick it up — it could
not, because `main` had never been rebuilt and the runtime reads `main`. Cost them a pointless
restart. **Getting a patch into a running tool is three steps, and skipping any one of them looks
identical to the fix not working:**
  1. **Rebuild the stack** so `main` carries the patch:
    `gh workflow run patch-stack-sync.yml --repo <owner>/<repo>` (it also runs nightly at 04:00
     UTC). Verify with `git grep <new-symbol> origin/main -- <path>` after a fetch.
  2. **Update the installed clone** — `pi` installs git packages to
    `~/.pi/agent/git/<host>/<owner>/<repo>`, a *separate* clone from any `$PROJECTS` checkout or
     worktree, and nothing re-pulls it: `pi update git:github.com/<owner>/<repo>`. Note the
     `git:` **prefix is required**; the bare form fails with `No matching package found` plus a
     hint. Confirm the clone actually moved with `git -C <clone> log --oneline -1`.
  3. **Restart pi** — the extension is already loaded in memory, so a correct on-disk fix changes
    nothing until the process restarts.

**Before committing:**

1. Re-read your changes for unnecessary complexity, redundant code, and unclear naming
2. Run relevant tests — not the full suite
3. Run linters and type checker — fix everything before committing

**Commits:** Imperative mood, ≤72 char subject line, one logical change per commit. Never push directly to main — use feature branches and PRs. Never commit secrets.

**Never override git identity on commit.** Do not use `git -c user.email=... -c user.name=... commit` or pass `--author`. The user has global git config set; trust it. This habit comes from ephemeral CI/sandbox environments and does not belong on a developer workstation.

**Merging:** Prefer squash merges to keep the main branch history linear and readable. Use `gh pr merge --squash`.

## Project Organisation

- **Use Go-style folder structure for repositories in $PROJECTS/**
- Organise repositories using the pattern: `$PROJECTS/domain.com/organisation/repository`
- Examples:
  - `$PROJECTS/github.com/TypeCellOS/BlockNote`
  - `$PROJECTS/registry.tiptap.dev/@tiptap-pro/extension-ai`



### Worktrees

- Put git worktrees under `.data/worktrees/` inside the repo root, not as sibling directories or in ad hoc temp locations.
- **Never build a branch in the root checkout — on a repo with parallel sessions it carries other people's unpushed commits.** Committing on the root checkout's `main` silently adopts whatever is sitting there: one night a branch built that way swept in another session's unpushed `docs(todo)` commit, and the subsequent `git reset --hard origin/main` would have destroyed it. Always `git worktree add` first, and **before your first commit run `git log --oneline origin/main..HEAD` and confirm every commit is yours.** If you find a foreign commit, branch it off to rescue it before resetting anything, and tell the user — it is not yours to push or drop.
- The worktree-create helper's `uv sync` may omit dev extras; run `uv sync --extra dev` in a new worktree before expecting `pytest`/`ruff`/`ty` to exist.
- **Check whether `.data` is a symlink before running two lanes concurrently.** Worktrees are inconsistent about it — some get a real `.data` dir, some get a **symlink to the root checkout's** — so two lanes running the same script from symlinked worktrees write into **one shared output tree**, last-writer-wins, silently interleaving results produced by *different code versions*. One night this left two `summary.json` writes 4 s apart disagreeing on a published count, and it looked exactly like non-determinism in the algorithm. Verify with `readlink <worktree>/.data`; if shared, give each lane a distinct output subdir or serialise them. Corollary: **an unexplained divergence in generated artifacts is a concurrency suspect before it is a numerical one** — and refusing to publish until it is explained is the right call, not fussiness.
- Audit worktrees regularly: list them, verify they still map to active branches/PRs, and check for stale or abandoned work.
- Clean worktrees regularly: remove merged or unused worktrees promptly so local state stays understandable and disk usage stays bounded.



### PR workflow

- **Before pushing any fix to a branch, check** `gh pr view <n> --json state,mergedAt`**.** If the PR is already merged, push to a new branch off `main` and open a fresh PR instead.
- **Edit PR descriptions with** `gh api`**, not** `gh pr edit`**.** In gantry/CI containers the injected `GITHUB_TOKEN` is a classic PAT whose scopes you should read off `gh auth status` rather than assume — historically `repo`+`workflow` only, i.e. no `read:org`. `gh pr edit` fetches the PR through a GraphQL query whose `reviewRequests` selection carries a `Team` fragment (`organization{login}`, `name`, `slug`) requiring `read:org`, so it **fails closed** — exit 1, nothing written, because the scope is needed by the *read* that precedes the write, not by the write. That bites even a body-only edit on a solo repo (`gh auth status` self-reports "Missing required token scopes: 'read:org'"). The same `read:org`-gated team/org fields break `gh pr create --reviewer <org>/<team>`; `--reviewer <user>` resolves via `assignableUsers` and needs no extra scope. The error arrives as GraphQL `INSUFFICIENT_SCOPES` inside an HTTP **200**, so grep exit codes, not status codes. Use `gh api --method PATCH repos/<owner>/<repo>/pulls/<n> -F body=@body.md` — scope-free and verified. Read commands (`gh pr view`, `gh pr status`) are unaffected. `gh auth refresh` can't add the scope in-container (the env token is immutable), so the scope has to go on the PAT itself — and **the operator call (2026-07-28) is to add it fleet-wide**: `read:org` is read-only org/team metadata, the `gh pr edit` UX is worth having everywhere, and a classic PAT's scopes are editable in place, so it needs no rotation and no turnstile `proxy.env` change. Until `gh auth status` shows `read:org`, use the REST PATCH — and keep preferring it for `-F body=@file` writes regardless: one call, no GraphQL preflight, immune to scope drift.



## Pixel-precise user input — build a picker, don't iterate through prose

When the answer is a single point or value on an image (crop coordinate, bounding box, mask, hex colour from a screenshot), **build a click-to-specify HTML tool from the start** instead of iterating through prose feedback like "a bit more to the left... too much... slightly up".

**Why:** prose feedback on visual positions loses ~100 px per round trip. Reading compressed chat thumbnails back and applying an inverse offset compounds the error. On one crop task I averaged ~150 px absolute error across 7 images after 4+ rounds of prose corrections; the user's first pass through a click tool was pixel-perfect.

**How to apply:**

- Heuristic: if you find yourself asking "is that enough? a bit more?" about a spatial quantity, stop and build the tool.
- Minimum viable picker: one static HTML page, `python3 -m http.server` in `/tmp/<tool>/`, click handler that writes the chosen value to `window.__RESULT__`. Playwriter reads it back, or the user pastes a generated bash command.
- Persist the originals somewhere stable (`/tmp/<tool>-backup/`) so you can re-crop non-destructively after the user adjusts.



## Hand me one command, never a procedure

**Any time you'd ask me to run more than a short one-liner, stop and collapse it into a single
copy-paste command.** If your instruction to me is shaping up to be a numbered list of shell steps
(or one long chained pipeline I'm meant to assemble), you're not done — stage everything yourself
and hand me exactly one invocation. This is most common when a step needs my *interactive* session
that you can't reach headlessly: macOS Keychain-backed browser cookies, an authenticated browser, a
desktop-app socket, a TTY, `sudo`.

**Why:** a multi-step manual procedure is slow, error-prone, and shoves the work I delegated back
onto me — one vetted command is the whole point of delegating. (The Slack case: Keychain decryption
is blocked over your ssh, so instead of "do X, then Y, then Z in your terminal" you scp'd the
figures, wrote a self-contained runner, and added the missing `channels create` subcommand to the
skill — leaving me a single `bash …/post_touchstone.sh`.)

**How to apply:**

- **Stage, don't enumerate.** scp assets to the host that has the session, write a self-contained
runner script there, and add any missing CLI subcommand to the relevant skill — so the
human-facing surface is one command.
- **Don't bypass the boundary.** Never dump Keychain/cookies or otherwise work around the auth wall
(it gets blocked anyway and isn't yours to cross) — run the sanctioned tool where the session
already lives, via the one command.
- **Make the command robust:** idempotent / safe to re-run, an obvious env override
(`BROWSER=chrome …`), parse whatever it needs from intermediate output, and degrade gracefully
(skip-and-continue on a soft failure, never half-finish).
- **State the one boundary in one line** (why it can't be fully headless), then give the command,
and offer to show me the staged script if I want to eyeball it first.



## Turn the verification discipline inward

Every rule about not trusting a sub-agent's self-report applies to **your own inferences**, and that
is the direction it gets skipped. A session spent writing falsification requirements into worker
briefs — which caught real problems — still lost ~10 hours to four self-inflicted stalls, each one an
inference accepted without the check it demanded of others.

- **Consistency is not confirmation.** Six identical `401`s felt like proof a token had expired; it
  had not, every call was to the wrong API. Two nodes failing identically felt like a cluster-wide
  fault; it was one artifact logged twice. When N attempts agree, ask whether they share one
  assumption — repeating a wrong premise produces consistency, not evidence.
- **Before declaring a credential dead, read the code that consumes it.** Grep the consumer for its
  base URL and auth header. The token above authenticated against a Cloudflare Worker proxy whose
  hostname was printed in the consuming library's own error message.
- **Source every dotenv, not the one you thought of.** `.env` *and* `.env.shared` (and any
  `.env.*`). One unsourced file produced a confident, wrong conclusion that a private model was
  permanently unreachable, and a plan built on top of it.
- **When the user challenges a factual claim, re-check before defending it.** Two direct questions
  ("are we rsyncing the whole directory?", "the token shouldn't have expired?") were answered from
  inference when a five-second check was available. Both answers were wrong.

## Performance bugs: read the traces you already have, then instrument the phases — never fix on a plausible suspect

A slow fan-out with an **idle** downstream resource means something serialises between the pool
and the wire — and which something is a measurement, not an inference. One night (2026-08-19,
the guard serve-leg re-score) a 1,460-row cell ran ~20 min against a GPU showing `Running: 0-1`:
three plausible root causes died by evidence before the real one — a cache lock on a network FS
(refuted on magnitude: 20 ms/op × 1,460 ≈ 30 s, not 20 min), a timeout-retry storm (refuted: the
timeout was 1800 s and the log held **zero** retry warnings), an AIMD gate collapse (refuted:
every cut logs, zero cut lines). The real cause — a per-row `endpoint()` resolve whose waiting
threads collectively stormed `squeue` probes — was finally caught **in logs that already
existed**. The fix-on-suspect version of that night rewrites the cache lock and ships a
regression that fixes nothing.

- **We under-utilise the traces we already have. Exhaust them first** — and read the
  *counterpart's* log, not just your own: the client's story (no retries, no gate cuts) and the
  server's story (`Running:` counters sawtoothing 0-13 with `Waiting: 0`) together localised the
  bug to "between the pool and the wire" with no new code. Loguru file sinks under `.data/logs/`,
  the profiling dumps every script already writes, vLLM engine counters, Slurm job logs — most
  hypotheses can be killed with what is already on disk.
- **The absence of an expected log line is evidence.** A gate cut that always logs and didn't
  log rules the gate out — grep for the warning you *would* see, and let zero hits count.
- **Sample the whole window, not the tail.** The `Running: 0-1` read came from the last two
  minutes of a 24-minute cell (the straggler tail) and nearly mis-shaped the fix; the full-window
  series showed the real signature — bursts of ~8-13 with idle gaps.
- **A hypothesis must predict the measured magnitude, not just the direction.** Every wrong
  suspect that night pointed the right way and was off by 40×. Do the arithmetic against the
  observed wall time before writing any fix.
- **When the existing traces cannot attribute the time, wrap the seams with timers** — a
  throwaway phase-bench (resolve / cache get / gate / HTTP / cache set, plus an in-flight gauge
  and a per-30s throughput series) attributes a pipeline in one run. Then fix the phase that
  owns the time, and keep the bench as the before/after proof.

## Background jobs: never pattern-match on process names

`pgrep -f <pattern>` matches **your own command line**, including the shell that *wrote* the script.
A supervisor whose wait loop greps for the thing it launches will match the heredoc that created it
and block forever — this cost ten hours twice in one session, the second time after "fixing" it by
changing the pattern.

- **Use a PID file or a lock file**, never a name pattern: write `$!` on launch, and test with
  `kill -0 "$pid"`.
- **If you must grep, exclude self**: `pgrep -f "$pat" | grep -v $$`, and never let the pattern
  appear in the launching command line (write the script with a file write, not a heredoc).
- **A backgrounded job that shows no progress is not necessarily slow — check what is matching**
  before concluding the work is stuck. `pgrep -af <pattern>` shows the full command lines; if the
  only hits are your own tooling, the job already finished or never started.
- **Detach properly**: `setsid` + `</dev/null` + `disown`. A plain `&` is killed with its process
  group. And do not `kill` a stale shell without checking it is not an ancestor of the command you
  are currently running — that takes your own work down with it.

## Destructive commands: never under a timeout, never on shared storage without ownership checks

- **`rm -rf` is banned** (use `trash`), and on a remote host without `trash` the substitute is an
  explicit, verified path — not a recursive delete wrapped in `ssh ... timeout`. A timeout that fires
  mid-delete leaves a **half-removed tree** and no error, and the absence of the confirmation line is
  the only signal. That happened: `entries=11` before, 7 after, no "removed" ever printed, and the
  later `ls` was misread as success.
- **On shared storage, check ownership before every delete.** `/workspace-vast` held directories
  literally named `$(whoami)` and `${whoami}` — unexpanded variables written as paths — owned by
  *other people* and holding 197 GB and 874 GB. They look exactly like the accidental copies you were
  asked to clean up. `stat -c %U` first, and refuse anything not yours.
- **Know what you are deleting.** A `.data/worktrees` on a cluster was job-isolation state belonging
  to the scheduler, not synced junk; the sync had excluded `.data` all along.

## Session Insights & Memory

- After completing significant work, or the session required a user intervention / rejected tool usage, offer to review and save insights to AGENTS.md
- After ANY correction from the user: capture the pattern and write a rule that prevents the same mistake. Ruthlessly iterate on these rules until mistake rate drops.



## Session Artifacts — long output goes in files, not the chat

Anything over ~40 lines — tool output, grep results, sub-agent reports,
log dumps, API responses, raw evidence — goes into a file (e.g.
`artifacts/<name>.md` or under `/tmp/`) with a short summary in the
main thread, never pasted back verbatim. The chat context budget is for
**decisions**, not evidence.

Paste inline only:

- Short log snippets (<20 lines) directly relevant to the next decision.
- The 1-2 lines of a stack trace that pinpoint the bug.
- Exact commands the user should run.

Sub-agents should write detail to a file and end with a short summary
(≤ 15 lines) plus the file path; the parent reads the file only when
the next step needs it. Never dump a 2000-line file into the chat to
"make sure the other side can see it" — the other side is the same
token budget.

### Capture full output to `.data/` — don't truncate with `tail`/`head`

When a command's output matters for debugging, `tee` **or redirect the
full output to a file under** `.data/` **(gitignored), then inspect the file**
— do not pipe straight through `| tail -25` / `| head`. Truncation throws
away exactly the lines you'll need two steps later (the first error, the
stack frame above the one you saw, the warning before the failure), and
re-running to "get the rest" is slow and often non-deterministic
(timestamps, ports, random seeds, flaky networks). Capturing once and
grepping the file is ~100× faster to debug than re-running with different
truncation each time.

- **Do:** `cmd 2>&1 | tee .data/run-<name>.log` then
`rg -n "error|warn|traceback" .data/run-<name>.log` (or read the file,
with offset/limit for big ones). The full log stays on disk for the
whole session.
- **For long-running jobs:** redirect and background —
`cmd >.data/<name>.log 2>&1 &` — then `tail -f`/`rg` the file as needed
instead of blocking on a truncated pipe.
- `tail`**/**`head` **are fine** for a genuine one-glance sanity check on
output you will never need again (e.g. `ls | head`), or to preview the
*tail of a file you already captured* (`tail -50 .data/<name>.log`).
The anti-pattern is discarding un-captured output through a truncating
pipe.
- Put these under `.data/` (already the convention for worktrees), keep
it gitignored, and prefer a descriptive `<name>` so parallel runs don't
clobber each other.



## Git Hygiene

- **Always gitignore** `.agents/settings.local.json` (and `.claude/settings.local.json`) - If you see these files in `git status` or `git diff`, add them to `.gitignore` before committing. These files contain local permissions and should never be tracked.
- **Encrypted-at-rest files → keep their contents out of plaintext git metadata.** Some repos encrypt sensitive files at rest (glassine: `filter=glassine` in `.gitattributes`; verify a specific path with `git check-attr filter -- <file>`). The committed blob and the diff are ciphertext, so committing the *change* is safe — but the branch name, commit message, PR title/description, issue text, and review comments are all plaintext (and public if the repo is — assume public unless you've confirmed otherwise). Before writing any of those for a change that touches an encrypted file, check whether it's encrypted, then keep the public-facing text generic: never name the secrets, credentials, internal hostnames, service/workspace names, or architecture details that the encryption exists to hide. Put the real rationale in a comment *inside* the encrypted file, where it's protected. If you've already pushed something leaky, amend + force-push and re-edit the PR/issue text before merging. Branch names are the exception: GitHub keeps the head branch name on a PR forever, even after the branch is deleted — so pick a generic branch name (`topology-refresh`, not `topology-<hostname>`) *before* pushing; there is no after-the-fact fix.



## MCP Servers (mcporter)


| server                      | description                                                                                        |
| --------------------------- | -------------------------------------------------------------------------------------------------- |
| `context7`                  | Look up live documentation and code examples for any library/framework via Context7                |
| `figma-dev-mode-mcp-server` | Figma Dev Mode — inspect designs and pull code/context from Figma frames (remote, `mcp.figma.com`) |
| `playwriter`                | Control Chrome via Playwright — browser automation, scraping, testing, and recording               |




## References

- [trailofbits/claude-code-config](https://github.com/trailofbits/claude-code-config) - Security-hardened Claude Code configuration
- [trailofbits/skills](https://github.com/trailofbits/skills) - Security auditing, code analysis, and development workflows
- [trailofbits/skills-curated](https://github.com/trailofbits/skills-curated) - Curated skill collection
- [obra/superpowers](https://github.com/obra/superpowers) - Workflow discipline skills
- [anthropics/claude-code](https://github.com/anthropics/claude-code) - Official plugins (frontend-design, pr-review-toolkit)

