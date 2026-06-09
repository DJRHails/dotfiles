# Code Style Patterns

Worked examples for the conventions summarized in [SKILL.md](../SKILL.md): the "flat
first" refactoring philosophy, guard clauses, data structures, imports, test factories,
and settings classes.

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

## Guard Clause Pattern

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

## Dataclass Defaults

Use dataclasses sparingly for internal structures; prefer `kw_only=True` and
`frozen=True` when appropriate:

```python
@dataclass(kw_only=True, frozen=True)
class Config:
    host: str
    port: int = 8080
```

## Import Conventions

Order imports standard library -> third-party -> local, separated by blank lines:

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

## Test Factory Pattern with Relationships

When using `factory_boy` with `SubFactory` relationships, always pass the relationship object, not the ID:

```python
# Wrong - LazyAttribute will override the ID
parent = ParentFactory.create()
child = ChildFactory.create(parent_id=parent.id)

# Correct - Pass the object itself
parent = ParentFactory.create()
child = ChildFactory.create(parent=parent)
```

## Settings Classes

Use Pydantic `BaseSettings` with type validation, environment-based config, and
`@lru_cache` on settings factory methods (singleton pattern):

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        case_sensitive=False,
        env_file=[".env"],
        extra="ignore",
    )
```
