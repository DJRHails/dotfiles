# Global Development Standards

Global instructions for all projects. Project-specific CLAUDE.md files override these defaults.

## Philosophy

- **No speculative features** - Don't add features, flags, or configuration unless users actively need them
- **No premature abstraction** - Don't create utilities until you've written the same code three times
- **Clarity over cleverness** - Prefer explicit, readable code over dense one-liners
- **Justify new dependencies** - Each dependency is attack surface and maintenance burden
- **Replace, don't deprecate** - When a new implementation replaces an old one, remove the old one entirely. No backward-compatible shims, dual config formats, or migration paths. Proactively flag dead code.
- **Verify at every level** - Set up automated guardrails (linters, type checkers, pre-commit hooks, tests) as the first step, not an afterthought. Prefer structure-aware tools (ast-grep, LSPs, compilers) over text pattern matching.
- **Bias toward action** - Decide and move for anything easily reversed; state your assumption so the reasoning is visible. Ask before committing to interfaces, data models, architecture, or destructive operations.
- **Finish the job** - Handle the edge cases you can see. Clean up what you touched. If something is broken adjacent to your change, flag it. But don't invent new scope.
- **Falsify, first** - When I report a bug, don't start by trying to fix it. Instead, start by writing a test that reproduces the bug. Then, have subagents try to fix the bug and prove it with a passing test.

## Code Quality

### Hard limits

1. ≤100 lines/function, cyclomatic complexity ≤8
2. ≤5 positional params
3. 100-char line length
4. Absolute imports only — no relative (`..`) paths
5. Google-style docstrings on non-trivial public APIs

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
| `trash`        | rm         | `trash file` - moves to macOS Trash (recoverable). **Never use `rm -rf`** |

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

Pin actions to SHA hashes with version comments: `actions/checkout@<full-sha>  # vX.Y.Z` (use `persist-credentials: false`). Scan workflows with `zizmor` before committing.

### Docker

- Always check existing `.env` files before asking the user for env vars
- Running containers don't pick up `.env` changes — recreate containers (`docker compose up -d`), don't just restart them

## Workflow

**Before committing:**

1. Re-read your changes for unnecessary complexity, redundant code, and unclear naming
2. Run relevant tests — not the full suite
3. Run linters and type checker — fix everything before committing

**Commits:** Imperative mood, ≤72 char subject line, one logical change per commit. Never push directly to main — use feature branches and PRs. Never commit secrets.

**Merging:** Prefer squash merges to keep the main branch history linear and readable. Use `gh pr merge --squash`.

## Project Organisation

- **Use Go-style folder structure for repositories in $PROJECTS/**
- Organise repositories using the pattern: `$PROJECTS/domain.com/organisation/repository`
- Examples:
  - `$PROJECTS/github.com/TypeCellOS/BlockNote`
  - `$PROJECTS/registry.tiptap.dev/@tiptap-pro/extension-ai`

## Session Insights & Memory

- After completing significant work, or the session required a user intervention / rejected tool usage, offer to review and save insights to CLAUDE.md

## Markdown Structure (mdstruct)

Use `mdstruct` to split large markdown files into hierarchical folder structures, or join them back.

**Split a file by headers:**

```bash
mdstruct split path/to/file.md        # splits into path/to/file/
mdstruct split path/to/file.md -l 3   # split up to H3 level
```

**Join files back:**

```bash
mdstruct join path/to/folder/         # joins back into path/to/folder.md
```

**Auto-detect:**

```bash
mdstruct auto path/to/file            # splits .md file or joins folder
```

- Useful for breaking up large idea/note files into individual topics
- Each H2 becomes its own file, numbered for ordering
- Creates a README.md with the top-level content
- Original file is backed up to `/tmp/mdstruct/`
- **Parallel sub-agents**: Split a file, spawn sub-agents to work on individual sections concurrently, then join back

## Git Hygiene

- **Always gitignore `.claude/settings.local.json`** - If you see this file in `git status` or `git diff`, add it to `.gitignore` before committing. This file contains local Claude Code permissions and should never be tracked.

## References

- [trailofbits/claude-code-config](https://github.com/trailofbits/claude-code-config) - Security-hardened Claude Code configuration
- [trailofbits/skills](https://github.com/trailofbits/skills) - Security auditing, code analysis, and development workflows
- [trailofbits/skills-curated](https://github.com/trailofbits/skills-curated) - Curated skill collection
- [obra/superpowers](https://github.com/obra/superpowers) - Workflow discipline skills
- [anthropics/claude-code](https://github.com/anthropics/claude-code) - Official plugins (frontend-design, pr-review-toolkit)
