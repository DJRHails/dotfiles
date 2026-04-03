---
name: python-conventions
description: Python coding conventions, modern tooling, and project setup. Apply when writing or reviewing Python code, creating projects, writing scripts, or migrating from legacy tools. Covers uv, ruff, ty, type hints, code structure, async, testing, and project configuration.
source:
  - https://github.com/trailofbits/skills/tree/main/plugins/modern-python
---

# Python Conventions

Coding conventions and modern tooling for Python projects. Apply when writing or reviewing Python code, setting up new projects, or migrating from legacy tools.

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
| [prek](https://github.com/jdx/prek) | Pre-commit hooks | pre-commit (faster, Rust-native) |
| `uv_build` | Build backend | hatchling, setuptools |
| [Loguru](https://github.com/Delgan/loguru) | Logging | stdlib logging |

### Security Tools

| Tool | Purpose | When |
|------|---------|------|
| shellcheck | Shell script linting | pre-commit |
| detect-secrets | Secret detection | pre-commit |
| actionlint | Workflow syntax validation | pre-commit, CI |
| zizmor | Workflow security audit | pre-commit, CI |
| pip-audit | Dependency vulnerability scanning | CI, manual |
| Dependabot | Automated dependency updates | scheduled |

See [security-setup.md](./references/security-setup.md) for configuration.

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

Bootstrap with the Trail of Bits template (preconfigured tooling):

```bash
uvx cookiecutter gh:trailofbits/cookiecutter-python
```

Or manually:

```bash
uv init --package myproject && cd myproject
```

Configure pyproject.toml (see [pyproject.md](./references/pyproject.md) for complete reference):

```toml
[project]
name = "myproject"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []

[dependency-groups]
dev = [{include-group = "lint"}, {include-group = "test"}, {include-group = "audit"}]
lint = ["ruff", "ty"]
test = ["pytest", "pytest-cov"]
audit = ["pip-audit"]

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["ALL"]
ignore = ["D", "COM812", "ISC001"]

[tool.pytest]
addopts = ["--cov=myproject", "--cov-fail-under=80"]

[tool.ty.terminal]
error-on-warning = true

[tool.ty.environment]
python-version = "3.11"

[tool.ty.rules]
possibly-unresolved-reference = "error"
unused-ignore-comment = "warn"
```

Install: `uv sync --all-groups`

### Makefile

```makefile
.PHONY: dev lint format test build

dev:
	uv sync --all-groups

lint:
	uv run ruff format --check && uv run ruff check && uv run ty check src/

format:
	uv run ruff format .

test:
	uv run pytest

build:
	uv build
```

### uv Quick Reference

| Command | Description |
|---------|-------------|
| `uv init` / `uv init --package` | Create project / distributable package |
| `uv add <pkg>` / `uv add --group dev <pkg>` | Add dependency / dev dependency |
| `uv remove <pkg>` | Remove dependency |
| `uv sync` / `uv sync --all-groups` | Install deps / all groups |
| `uv run <cmd>` | Run command in venv |
| `uv run --with <pkg> <cmd>` | Run with temporary dependency |
| `uv build` / `uv publish` | Build / publish package |

See [uv-commands.md](./references/uv-commands.md) for complete reference.

## Core Principles

1. **Correctness above all else** - Code must work reliably in production
2. **Type Safety First** - Strict type hints throughout the codebase
3. **Performance at Scale** - Consider performance implications for large datasets
4. **Readability** - Self-documenting code through good naming and structure
5. **Functional over OOP** - Prefer functional approaches where appropriate
6. **Clarity over Cleverness** - Write code teammates can easily understand and debug

## Refactoring Philosophy: "Flat First"

### The Approach

1. **Write it flat first**: Get the entire logic working in one place so you can see the flow
2. **Then identify major sections**: Look for natural boundaries
3. **Extract only meaningful abstractions**: If a function doesn't represent a complete, _reusable_ concept, it probably shouldn't be a function

### When TO Extract Functions

Extract a function when it represents:
- **A complete business operation**: `create_order()`
- **A reusable utility**: `validate_phone_number()`
- **A complex algorithm**: `calculate_score()`
- **External integration**: `upload_file_to_s3()`

### When NOT to Extract Functions

Don't extract when it's just:
- **Simple data transformation**: `{item.id: item.name for item in items}`
- **Single-use lookups**: Finding items in a list/dict
- **Trivial operations**: Getting/setting single values
- **Breaking up linear flow**: Operations that naturally follow each other

### Example

```python
# Over-abstracted - too many tiny functions
def get_item_to_name_mapping():
    return {item.id: item.name for item in items}

def get_name_to_detail_mapping():
    return {name: detail for name, detail in name_details}

def get_item_to_detail_mapping():
    name_mapping = get_item_to_name_mapping()
    detail_mapping = get_name_to_detail_mapping()
    return combine_mappings(name_mapping, detail_mapping)

# Clear, flat approach
item_id_to_name = {item.id: item.name for item in items}
name_to_detail = {name: detail for name, detail in name_details}

results = []
for item_id in item_ids:
    name = item_id_to_name[item_id]
    detail = name_to_detail.get(name)
    if not detail:
        logger.warning(f"No detail found for item {item_id}")
        continue
    results.append(process(item_id, detail))
```

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
- **Dataclass**: Use sparingly for internal structures; prefer `kw_only=True` and `frozen=True` when appropriate:
  ```python
  @dataclass(kw_only=True, frozen=True)
  class Config:
      host: str
      port: int = 8080
  ```

## Project Structure

- **`src/` layout** for packages: `src/myproject/` not `myproject/`
- **`uv.lock` in git** for applications (reproducible deploys), `.gitignore` for libraries
- **PEP 723** for standalone scripts with dependencies:
  ```python
  # /// script
  # requires-python = ">=3.11"
  # dependencies = ["requests>=2.28", "rich"]
  # ///
  ```
  Run with `uv run script.py` — deps auto-installed, no project needed. See [pep723-scripts.md](./references/pep723-scripts.md).
- **Dependency groups** (PEP 735) for dev tooling:
  ```toml
  [dependency-groups]
  dev = [{include-group = "lint"}, {include-group = "test"}]
  lint = ["ruff", "ty"]
  test = ["pytest", "pytest-cov"]
  ```
- **Coverage enforcement**: `--cov-fail-under=80` in pytest config

## Code Structure

- **Flat is Better**: Follow the "flat first" approach
- **Function Parameters**: Force named parameters with `*` when >3 parameters
- **Imports**: Order as standard library -> third-party -> local, separated by blank lines
- **Reduce Cyclomatic Complexity**: Minimize through guard clauses and early returns
- **Linear Flow**: Keep related operations together instead of extracting tiny helpers

### Guard Clause Pattern

Prefer guard clauses with early returns over nested conditionals:

```python
# Guard clauses reduce nesting and complexity
def process_item(item: Item | None) -> Result:
    if not item:
        return Result.empty()

    if not item.is_active:
        logger.warning(f"Item {item.id} is not active")
        return Result.skipped()

    if not item.data:
        raise ValueError(f"Item {item.id} has no data")

    # Main logic at base indentation level
    return execute(item)
```

Use `continue` for guard clauses in loops:

```python
for contact in contacts:
    if not contact.email:
        continue
    if contact.is_unsubscribed:
        continue
    send_email(contact)
```

### Avoid Long If-Else Blocks

Use guards and let the end of the function be the implicit "else":

```python
def get_status(item: Item) -> Status:
    if item.is_cancelled:
        return Status.CANCELLED
    if item.is_completed:
        return Status.COMPLETED
    if not item.started_at:
        return Status.PENDING
    return Status.IN_PROGRESS
```

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

- **Discourage Docstrings**: Use type hints and good naming instead
- **Comments**: Explain _why_, not _what_
- **Path Handling**: Use `pathlib` over `os.path`
- **No Magic Numbers**: Use named constants
- **No Deep Inheritance**: Prefer composition

## Import Conventions

```python
# Standard library
from collections.abc import Collection, Sequence
from typing import Any, TypeVar
from uuid import UUID

# Third-party
from pydantic import BaseModel

# Local
from myproject.models import MyModel
```

- Use `from typing import TYPE_CHECKING` for circular import prevention
- Always use absolute imports for local modules
- Use `from module import specific_item` for frequently used items
- Use `import module` for modules used sparingly

## Testing Conventions

- **Runner**: pytest (see [testing.md](./references/testing.md))
- **Parametrized Tests**: Heavy use of `@pytest.mark.parametrize`
- **Test Organization**: Tests mirror source structure in `tests/` directories
- **Fixtures**: Defined in `conftest.py` files at appropriate levels
- **Async Tests**: Use `pytest-asyncio` for async test functions
- **No Mock Theater**: Don't test interactions between mocked objects - test real behavior
- **Test Naming**: `test_{function_name}_{scenario}` pattern
- **Test Structure**: Unit tests (no DB) -> Integration tests (mocked deps) -> E2E tests

### Factory Pattern with Relationships

When using `factory_boy` with `SubFactory` relationships, always pass the relationship object, not the ID:

```python
# Wrong - LazyAttribute will override the ID
parent = ParentFactory.create()
child = ChildFactory.create(parent_id=parent.id)

# Correct - Pass the object itself
parent = ParentFactory.create()
child = ChildFactory.create(parent=parent)
```

## Configuration

- **Settings Classes**: Use Pydantic `BaseSettings` with type validation
- **Environment-based**: Support multiple environments (test, dev, staging, prod)
- **Singleton Pattern**: Use `@lru_cache` on settings factory methods

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        case_sensitive=False,
        env_file=[".env"],
        extra="ignore",
    )
```

## Migration Guide

When migrating from legacy tooling, see [migration-checklist.md](./references/migration-checklist.md) for comprehensive steps.

### From requirements.txt + pip

**For standalone scripts**: Convert to PEP 723 inline metadata (see [pep723-scripts.md](./references/pep723-scripts.md))

**For projects**:
```bash
uv init --bare
# Add each dependency with uv (not by editing pyproject.toml)
uv add requests rich
uv sync
```

Then delete `requirements.txt`, `requirements-dev.txt`, and old virtualenvs.

### From setup.py / setup.cfg

1. `uv init --bare` to create pyproject.toml
2. `uv add` each dependency from `install_requires`
3. `uv add --group dev` for dev dependencies
4. Copy non-dependency metadata to `[project]`
5. Delete `setup.py`, `setup.cfg`, `MANIFEST.in`

### From flake8 + black + isort

1. Remove old tools, add ruff: `uv add --group dev ruff`
2. Delete `.flake8`, `[tool.black]`, `[tool.isort]` configs
3. Add ruff configuration (see [ruff-config.md](./references/ruff-config.md))
4. Run `uv run ruff check --fix . && uv run ruff format .`

### From mypy / pyright

1. Remove old tools, add ty: `uv add --group dev ty`
2. Delete `mypy.ini`, `pyrightconfig.json`, or `[tool.mypy]`/`[tool.pyright]` sections
3. Run `uv run ty check src/`

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
- **Docstring Overuse**: Let types and names document the code
- **Race Conditions**: Ensure atomic operations for critical data
- **Inconsistent Async/Sync**: Don't mark functions `async` unless they `await`
- **Manual virtualenv activation**: Use `uv run` instead
- **Editing pyproject.toml deps by hand**: Use `uv add` / `uv remove`

## Shared Code

- **Threshold**: Extract to shared modules after 3 usages
- **Location**: Use a `shared/` or `common/` directory for cross-module utilities

## Reference Docs

- [pyproject.md](./references/pyproject.md) - Complete pyproject.toml reference
- [uv-commands.md](./references/uv-commands.md) - uv command reference
- [ruff-config.md](./references/ruff-config.md) - Ruff linting/formatting configuration
- [testing.md](./references/testing.md) - pytest and coverage setup
- [pep723-scripts.md](./references/pep723-scripts.md) - PEP 723 inline script metadata
- [prek.md](./references/prek.md) - Fast pre-commit hooks with prek
- [security-setup.md](./references/security-setup.md) - Security hooks and dependency scanning
- [dependabot.md](./references/dependabot.md) - Automated dependency updates
- [migration-checklist.md](./references/migration-checklist.md) - Step-by-step migration cleanup
