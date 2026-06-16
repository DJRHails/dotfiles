# Global Development Standards

Global instructions for all projects. Project-specific AGENTS.md (or CLAUDE.md) files override these defaults.

## Philosophy

- **No speculative features** - Don't add features, flags, or configuration unless users actively need them
- **No premature abstraction** - Don't create utilities until you've written the same code three times
- **Clarity over cleverness** - Prefer explicit, readable code over dense one-liners
- **Justify new dependencies** - Each dependency is attack surface and maintenance burden
- **Replace, don't deprecate** - When a new implementation replaces an old one, remove the old one entirely. No backward-compatible shims, dual config formats, or migration paths. Proactively flag dead code.
- **Verify at every level** - Set up automated guardrails (linters, type checkers, pre-commit hooks, tests) as the first step, not an afterthought. Prefer structure-aware tools (ast-grep, LSPs, compilers) over text pattern matching.
- **Bias toward action** - Decide and move for anything easily reversed; state your assumption so the reasoning is visible. Ask before committing to interfaces, data models, architecture, or destructive operations. When given a bug report, just fix it — don't ask for hand-holding. Point at logs, errors, failing tests, then resolve them. Zero context switching required from the user.
- **Confirm before contacting other humans** - Any action that delivers a message to someone other than me — sending email, posting Slack into a channel/DM with anyone else in it, creating or updating a calendar event with attendees (or `--send-updates` anything other than `none`), opening/commenting/merging GitHub PRs and issues, posting to Linear/Notion/Jira where teammates are notified, or any webhook/API call that reaches a person — requires you to first post a short summary (recipients, subject/title, body, timing) and then wait for my explicit "yes" / "send it" / "go ahead". My initial request ("send the invite to X", "reply to this email", "message Alice") is the trigger, not the authorization. Drafts and local-only artifacts that don't notify anyone are exempt. **Exempt: GitHub PRs and issues on my own personal repos (`github.com/DJRHails/*`) — open, comment, and merge them freely without a confirmation step, since they're solo repos that notify no one else.** The confirmation step still applies to repos in shared orgs (e.g. `safety-research`) or any repo with other collaborators.
- **Finish the job** - Handle the edge cases you can see. Clean up what you touched. If something is broken adjacent to your change, flag it. But don't invent new scope.
- **Falsify, first** - When I report a bug, don't start by trying to fix it. Instead, start by writing a test that reproduces the bug. Then, have subagents try to fix the bug and prove it with a passing test.
- **Prove it works** - Never mark a task complete without demonstrating correctness. Run tests, check logs, diff behavior. Ask: "Would a staff engineer approve this?"

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

| tool           | replaces   | usage                                                                     |
| -------------- | ---------- | ------------------------------------------------------------------------- |
| `rg` (ripgrep) | grep       | `rg "pattern"` - fast regex search                                        |
| `fd`           | find       | `fd "*.py"` - fast file finder                                            |
| `ast-grep`     | -          | `ast-grep --pattern '$FUNC($$$)' --lang py` - AST-based code search       |
| `shellcheck`   | -          | `shellcheck script.sh` - shell script linter                              |
| `shfmt`        | -          | `shfmt -i 2 -w script.sh` - shell formatter                               |
| `actionlint`   | -          | `actionlint .github/workflows/` - GitHub Actions linter                   |
| `zizmor`       | -          | `zizmor .github/workflows/` - Actions security audit                      |
| `prek`         | pre-commit | `prek run` - fast git hooks (Rust, no Python)                             |
| `trash`        | rm         | `trash file` - moves to the OS trash (recoverable). **Never use `rm -rf`** |

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
- Audit worktrees regularly: list them, verify they still map to active branches/PRs, and check for stale or abandoned work.
- Clean worktrees regularly: remove merged or unused worktrees promptly so local state stays understandable and disk usage stays bounded.

### PR workflow

- **Before pushing any fix to a branch, check `gh pr view <n> --json state,mergedAt`.** If the PR is already merged, push to a new branch off `main` and open a fresh PR instead.

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

## Git Hygiene

- **Always gitignore `.agents/settings.local.json`** (and `.claude/settings.local.json`) - If you see these files in `git status` or `git diff`, add them to `.gitignore` before committing. These files contain local permissions and should never be tracked.
- **Encrypted-at-rest files → keep their contents out of plaintext git metadata.** Some repos encrypt sensitive files at rest (transcrypt: `filter=crypt` in `.gitattributes`; verify a specific path with `git check-attr filter -- <file>`). The committed blob and the diff are ciphertext, so committing the *change* is safe — but the commit message, PR title/description, issue text, and review comments are all plaintext (and public if the repo is — assume public unless you've confirmed otherwise). Before writing any of those for a change that touches an encrypted file, check whether it's encrypted, then keep the public-facing text generic: never name the secrets, credentials, internal hostnames, service/workspace names, or architecture details that the encryption exists to hide. Put the real rationale in a comment *inside* the encrypted file, where it's protected. If you've already pushed something leaky, amend + force-push and re-edit the PR/issue text before merging.

## MCP Servers (mcporter)

| server | description |
| --- | --- |
| `context7` | Look up live documentation and code examples for any library/framework via Context7 |
| `figma-dev-mode-mcp-server` | Figma Dev Mode — inspect designs and pull code/context from Figma frames (remote, `mcp.figma.com`) |
| `playwriter` | Control Chrome via Playwright — browser automation, scraping, testing, and recording |

## References

- [trailofbits/claude-code-config](https://github.com/trailofbits/claude-code-config) - Security-hardened Claude Code configuration
- [trailofbits/skills](https://github.com/trailofbits/skills) - Security auditing, code analysis, and development workflows
- [trailofbits/skills-curated](https://github.com/trailofbits/skills-curated) - Curated skill collection
- [obra/superpowers](https://github.com/obra/superpowers) - Workflow discipline skills
- [anthropics/claude-code](https://github.com/anthropics/claude-code) - Official plugins (frontend-design, pr-review-toolkit)
