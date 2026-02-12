---
name: python-conventions
description: Python coding conventions and best practices. Apply when writing or reviewing Python code. Covers type hints, code structure, async patterns, testing, naming, and error handling.
---

# Python Conventions

Coding conventions for Python projects. Apply these when writing or reviewing Python code.

## Toolchain

- **Package Manager**: [uv](https://docs.astral.sh/uv/) for project setup, dependency management, and virtual environments
- **Formatting**: [Ruff](https://docs.astral.sh/ruff/) for formatting and linting
- **Type Checking**: [ty](https://github.com/astral-sh/ty) for type checking
- **Testing**: [pytest](https://docs.pytest.org/) as the test runner
- **Logging**: [Loguru](https://github.com/Delgan/loguru) for logging

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
# ❌ Over-abstracted - too many tiny functions
def get_item_to_name_mapping():
    return {item.id: item.name for item in items}

def get_name_to_detail_mapping():
    return {name: detail for name, detail in name_details}

def get_item_to_detail_mapping():
    name_mapping = get_item_to_name_mapping()
    detail_mapping = get_name_to_detail_mapping()
    return combine_mappings(name_mapping, detail_mapping)

# ✅ Clear, flat approach
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

## Code Structure

- **Flat is Better**: Follow the "flat first" approach
- **Function Parameters**: Force named parameters with `*` when >3 parameters
- **Imports**: Order as standard library → third-party → local, separated by blank lines
- **Reduce Cyclomatic Complexity**: Minimize through guard clauses and early returns
- **Linear Flow**: Keep related operations together instead of extracting tiny helpers

### Guard Clause Pattern

Prefer guard clauses with early returns over nested conditionals:

```python
# ✅ Guard clauses reduce nesting and complexity
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

# ❌ Nested conditionals increase complexity
def process_item(item: Item | None) -> Result:
    if item:
        if item.is_active:
            if item.data:
                return execute(item)
            else:
                raise ValueError(f"Item {item.id} has no data")
        else:
            logger.warning(f"Item {item.id} is not active")
            return Result.skipped()
    else:
        return Result.empty()
```

Use `continue` for guard clauses in loops:

```python
# ✅ Guards with continue
for contact in contacts:
    if not contact.email:
        continue
    if contact.is_unsubscribed:
        continue
    send_email(contact)
```

### Avoid Long If-Else Blocks

When `if` and `else` are separated by many lines, it becomes hard to understand what condition triggers the `else`. Use guards and let the end of the function be the implicit "else":

```python
# ✅ Guards handle edge cases, default case falls through
def get_status(item: Item) -> Status:
    if item.is_cancelled:
        return Status.CANCELLED
    if item.is_completed:
        return Status.COMPLETED
    if not item.started_at:
        return Status.PENDING
    return Status.IN_PROGRESS

# ❌ else is far from if, hard to follow
def get_status(item: Item) -> Status:
    if item.is_cancelled:
        return Status.CANCELLED
    elif item.is_completed:
        return Status.COMPLETED
    elif not item.started_at:
        return Status.PENDING
    else:
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

- **Runner**: pytest
- **Parametrized Tests**: Heavy use of `@pytest.mark.parametrize`
- **Test Organization**: Tests mirror source structure in `tests/` directories
- **Fixtures**: Defined in `conftest.py` files at appropriate levels
- **Async Tests**: Use `pytest-asyncio` for async test functions
- **No Mock Theater**: Don't test interactions between mocked objects - test real behavior
- **Test Naming**: `test_{function_name}_{scenario}` pattern
- **Test Structure**: Unit tests (no DB) → Integration tests (mocked deps) → E2E tests

### Factory Pattern with Relationships

When using `factory_boy` with `SubFactory` relationships, always pass the relationship object, not the ID:

```python
# ❌ Wrong - LazyAttribute will override the ID
parent = ParentFactory.create()
child = ChildFactory.create(parent_id=parent.id)

# ✅ Correct - Pass the object itself
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

## Shared Code

- **Threshold**: Extract to shared modules after 3 usages
- **Location**: Use a `shared/` or `common/` directory for cross-module utilities
