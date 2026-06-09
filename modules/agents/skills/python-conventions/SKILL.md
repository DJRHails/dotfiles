---
name: python-conventions
description: Python coding conventions, modern tooling, and project setup. Apply when writing or reviewing Python code, creating projects, writing scripts, or migrating from legacy tools. Covers uv, ruff, ty, type hints, code structure, async, testing, and project configuration.
source:
  - https://github.com/trailofbits/skills/tree/main/plugins/modern-python
---

# Python Conventions

Coding conventions and modern tooling for Python projects. Apply when writing or reviewing Python code, setting up new projects, or migrating from legacy tools. This file is the summary; worked examples and full configs live in [references/](references/).

## Decision Tree

```
What are you doing?
|
+- Single-file script with dependencies?
|   -> Use PEP 723 inline metadata (./references/pep723-scripts.md)
|
+- New multi-file project (not distributed)?
|   -> Minimal uv setup (see Project Setup below)
|
+- New reusable package/library?
|   -> Full project setup (see Project Setup below)
|
+- Migrating existing project?
|   -> See Migration Guide below
|
+- Writing or reviewing code?
    -> See conventions below
```

## Toolchain

| Tool | Purpose | Replaces |
|------|---------|----------|
| [uv](https://docs.astral.sh/uv/) | Package/dependency management | pip, virtualenv, pip-tools, pipx, pyenv |
| [ruff](https://docs.astral.sh/ruff/) | Linting and formatting | flake8, black, isort, pyupgrade, pydocstyle |
| [ty](https://github.com/astral-sh/ty) | Type checking | mypy, pyright |
| [pytest](https://docs.pytest.org/) | Testing with coverage | unittest |
| [prek](https://github.com/j178/prek) | Pre-commit hooks | pre-commit (faster, Rust-native) |
| `uv_build` | Build backend | hatchling, setuptools |
| [Loguru](https://github.com/Delgan/loguru) | Logging | stdlib logging |

### Security Tools

shellcheck, detect-secrets, actionlint, zizmor (pre-commit); pip-audit and Dependabot for dependencies. Configuration: [security-setup.md](./references/security-setup.md) and [dependabot.md](./references/dependabot.md).

### Legacy Tool Migration

| Avoid | Use Instead |
|-------|-------------|
| `pip install` / `pip freeze` | `uv add` / `uv export` |
| `python -m venv` / `source .venv/bin/activate` | `uv sync` / `uv run <cmd>` |
| `pipx install` | `uv tool install` |
| `requirements.txt` | `pyproject.toml` (projects) or PEP 723 (scripts) |
| `[project.optional-dependencies]` for dev tools | `[dependency-groups]` (PEP 735) |
| `[tool.ty]` python-version | `[tool.ty.environment]` python-version |
| `uv pip install` | `uv add` and `uv sync` |
| Poetry | uv |
| black / isort / flake8 / pylint | ruff |
| mypy / pyright | ty |
| pre-commit | prek |
| hatchling | uv_build |

**Key rules:**
- Always use `uv add` / `uv remove` to manage dependencies — never edit pyproject.toml deps by hand
- Never manually activate venvs — use `uv run` for all commands
- Use `[dependency-groups]` for dev/test/docs deps, not `[project.optional-dependencies]`
- Use `uv run --with <pkg>` for one-off commands needing packages not in your project

## Project Setup

### Minimal Project

```bash
uv init myproject && cd myproject
uv add requests rich
uv add --group dev pytest ruff ty
uv run python src/myproject/main.py
```

### Full Package

Bootstrap with `uvx cookiecutter gh:trailofbits/cookiecutter-python` (preconfigured Trail of Bits template) or `uv init --package myproject`. Configure pyproject.toml (complete example with ruff/ty/pytest/coverage sections: [pyproject.md](./references/pyproject.md)), then `uv sync --all-groups`. uv command reference and standard Makefile (dev/lint/format/test/build targets): [uv-commands.md](./references/uv-commands.md).

## Core Principles

1. **Correctness above all else** - Code must work reliably in production
2. **Type Safety First** - Strict type hints throughout the codebase
3. **Performance at Scale** - Consider performance implications for large datasets
4. **Readability** - Self-documenting code through good naming and structure
5. **Functional over OOP** - Prefer functional approaches where appropriate
6. **Clarity over Cleverness** - Write code teammates can easily understand and debug

## Refactoring Philosophy: "Flat First"

Write it flat first, then identify major sections, then extract only meaningful abstractions. Extract a function when it's a complete business operation, reusable utility, complex algorithm, or external integration. Don't extract for simple transformations, single-use lookups, trivial operations, or to break up linear flow. Worked example: [code-style.md](./references/code-style.md).

## Type Hints

- **Always Required**: Every function must have complete type annotations
- **Input Types**: Use `Sequence[T]` for input parameters (more flexible)
- **Return Types**: Use `list[T]` for return types (more specific)
- **Optionals**: Use `X | None` syntax (not `Optional[X]`)
- **Any Usage**: Acceptable for JSON payloads (`dict[str, Any]`) or when typing adds no value
- **Decorators**: Must be fully typed

## Data Structures

- **Protocols**: Preferred over ABCs for interface definitions
- **TypedDict**: Use when dictionary keys are known and static
- **BaseModel (Pydantic)**: Use for external API data
- **Dataclass**: Use sparingly for internal structures; prefer `kw_only=True` and `frozen=True` (example: [code-style.md](./references/code-style.md))

## Project Structure

- **`src/` layout** for packages: `src/myproject/` not `myproject/`
- **`uv.lock` in git** for applications (reproducible deploys), `.gitignore` for libraries
- **PEP 723** for standalone scripts with dependencies — run with `uv run script.py`, deps auto-installed, no project needed. See [pep723-scripts.md](./references/pep723-scripts.md)
- **Dependency groups** (PEP 735) for dev tooling: `[dependency-groups]` with `{include-group = "..."}` composition
- **Coverage enforcement**: `--cov-fail-under=80` in pytest config

## Code Structure

- **Flat is Better**: Follow the "flat first" approach
- **Function Parameters**: Force named parameters with `*` when >3 parameters
- **Imports**: Standard library -> third-party -> local, blank-line separated; absolute imports only; `TYPE_CHECKING` for circular import prevention; `from module import item` for frequently used items, `import module` for modules used sparingly (example: [code-style.md](./references/code-style.md))
- **Guard Clauses**: Prefer early returns over nested conditionals; use `continue` for guards in loops; let the end of the function be the implicit "else" instead of long if-else chains (examples: [code-style.md](./references/code-style.md))
- **Linear Flow**: Keep related operations together instead of extracting tiny helpers

## Database Patterns

- **ORM Preferred**: Use your ORM, avoid raw SQL
- **Bulk Operations**: Always prefer bulk operations over loops
- **Batch Functions**: Database functions should accept lists, not single items
- **N+1 Queries**: Must be avoided - use eager loading
- **Soft Deletes**: Default approach for data deletion
- **Nullable Datetimes over Booleans**: Prefer `deleted_at: datetime | None` over `is_deleted: bool` in database schemas - you get both the flag and the timestamp
- **UTC Only**: All database datetime fields must be UTC
- **Indexes**: Over-indexing is acceptable, missing indexes is unacceptable
- **UUIDv7 Primary Keys**: Use UUIDv7 for all primary keys (time-ordered, better indexing than UUIDv4)
- **Prefixed Public IDs**: Never expose raw UUIDs in APIs. Use `{entity}_{base62(uuid)}` format (e.g. `usr_2Jh5XQ...`, `thrd_7Km9...`). Implement as Pydantic `Annotated` types with `BeforeValidator` (deserialize) and `PlainSerializer` (serialize) so route handlers work with raw UUIDs internally while APIs always show prefixed IDs

## Performance Requirements

- **Pagination**: Required for all API list endpoints
- **Query Performance**: Consider performance at scale (1M+ rows)
- **Async I/O**: Always use async for I/O operations
- **Bulk Processing**: Default to bulk operations unless readability is severely impacted

## Async Patterns

- **Async by Default**: All I/O operations must be async
- **Concurrent Operations**: Use `asyncio.gather()` for parallel operations
- **Async Context Managers**: Use `async with` for resource management
- **Consistency**: Don't mark functions `async` unless they actually `await`

## API Design

- **Pagination**: All list endpoints must support pagination
- **Error Handling**: Use custom exceptions inheriting from appropriate built-ins
- **Partial Failures**: Use dicts to preserve successful outputs, log dropped elements

## Naming Conventions

- **Standard Python**: `module_name`, `ClassName`, `CONSTANT_NAME`, `function_name`
- **Booleans**: Prefer `is_valid` over `valid`
- **Searchable**: Names should be grep-friendly
- **Pronounceable**: Avoid cryptic abbreviations
- **Scope-Based Length**: Longer names for larger scopes

## Error Handling

- **Logging**: Log warnings at the source
- **Built-in Exceptions**: Prefer when appropriate (ValueError, TypeError, etc.)
- **Custom Exceptions**: Create with `{Context}Exception` naming when built-ins don't fit
- **Specific Catches**: Catch specific exceptions, not broad `Exception`
- **No Silent Failures**: Don't log errors and continue with invalid state

## Code Quality

- **Docstrings**: Google-style docstrings on non-trivial public APIs (global standard). Skip redundant docstrings on trivial, self-evident code — type hints and good naming carry that weight
- **Comments**: Explain _why_, not _what_
- **Path Handling**: Use `pathlib` over `os.path`
- **No Magic Numbers**: Use named constants
- **No Deep Inheritance**: Prefer composition

## Testing Conventions

- **Runner**: pytest with coverage (setup: [testing.md](./references/testing.md))
- **Parametrized Tests**: Heavy use of `@pytest.mark.parametrize`
- **Test Organization**: Tests mirror source structure in `tests/` directories
- **Fixtures**: Defined in `conftest.py` files at appropriate levels
- **Async Tests**: Use `pytest-asyncio` for async test functions
- **No Mock Theater**: Don't test interactions between mocked objects - test real behavior
- **Test Naming**: `test_{function_name}_{scenario}` pattern
- **Test Structure**: Unit tests (no DB) -> Integration tests (mocked deps) -> E2E tests
- **Factories**: With `factory_boy` `SubFactory` relationships, pass the object, not the ID (example: [code-style.md](./references/code-style.md))

## Configuration

- **Settings Classes**: Use Pydantic `BaseSettings` with type validation (example: [code-style.md](./references/code-style.md))
- **Environment-based**: Support multiple environments (test, dev, staging, prod)
- **Singleton Pattern**: Use `@lru_cache` on settings factory methods

## Migration Guide

Step-by-step recipes for migrating from requirements.txt + pip, setup.py/setup.cfg, flake8 + black + isort, and mypy/pyright — plus cleanup checklists, gradual ty adoption, and verification — live in [migration-checklist.md](./references/migration-checklist.md).

## Anti-Patterns to Avoid

- **Over-Abstraction**: Don't create tiny functions for simple operations
- **Brittle String Parsing**: `name.split("prefix: ")[1]` - use regex or structured data
- **Deep Inheritance**: Prefer composition
- **Silent Failures**: Don't swallow exceptions
- **Broad Exception Catching**: Catch specific exceptions
- **Synchronous I/O**: Always async for I/O
- **Missing Type Hints**: All functions must be typed
- **Boolean Database Fields**: Use nullable datetimes instead
- **N+1 Queries**: Always batch database operations
- **Nested Conditionals**: Use guard clauses
- **Docstring Overuse**: Don't restate what types and names already say; reserve docstrings for non-trivial public APIs (Google style)
- **Race Conditions**: Ensure atomic operations for critical data
- **Inconsistent Async/Sync**: Don't mark functions `async` unless they `await`
- **Manual virtualenv activation**: Use `uv run` instead
- **Editing pyproject.toml deps by hand**: Use `uv add` / `uv remove`

## Shared Code

- **Threshold**: Extract to shared modules after 3 usages
- **Location**: Use a `shared/` or `common/` directory for cross-module utilities

## Reference Docs

- [pyproject.md](./references/pyproject.md) - Complete pyproject.toml reference (incl. ruff/ty/pytest config)
- [uv-commands.md](./references/uv-commands.md) - uv command reference and project Makefile
- [code-style.md](./references/code-style.md) - Flat-first, guard clauses, imports, factories, settings (worked examples)
- [ruff-config.md](./references/ruff-config.md) - Ruff linting/formatting configuration
- [testing.md](./references/testing.md) - pytest and coverage setup
- [pep723-scripts.md](./references/pep723-scripts.md) - PEP 723 inline script metadata
- [prek.md](./references/prek.md) - Fast pre-commit hooks with prek
- [security-setup.md](./references/security-setup.md) - Security hooks and dependency scanning
- [dependabot.md](./references/dependabot.md) - Automated dependency updates
- [migration-checklist.md](./references/migration-checklist.md) - Migration recipes and cleanup checklist
