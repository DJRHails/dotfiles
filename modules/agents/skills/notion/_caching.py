"""Pickle-stable disk-backed memoization for bin/ scripts.

`@cached(cache)` decorates a function and stores its return value keyed on the
JSON-encoded arguments. Supports:

- Plain return types (str, int, dict, list, …): stored as-is.
- pydantic v2 `BaseModel` / `list[Model]` / `dict[str, Model]` returns: stored
  as dicts (via `model.model_dump()`) and rehydrated on read (via
  `Model.model_validate(...)`). This avoids the cross-invocation pickling
  pitfall where models defined in `__main__` can't be unpickled in a fresh
  process.
- `None` returns: cached correctly via a `_MISSING` sentinel (the previous
  implementation re-ran on every call for None-returning functions).
- Async functions (`async def`): result is awaited then cached; cache hits
  return a fresh coroutine wrapping the cached value.
"""

from __future__ import annotations

import asyncio
import functools
import hashlib
import inspect
import json
import logging
import types
import typing
from collections.abc import Callable
from typing import Any, TypeVar, Union

import diskcache

try:
    from pydantic import BaseModel
except ImportError:  # pragma: no cover — pydantic is optional for callers
    BaseModel = None  # type: ignore[assignment]

T = TypeVar("T")
logger = logging.getLogger(__name__)

# Sentinel for "key absent from cache" — lets None be a valid cached value.
_MISSING = object()


def safe_jsonable_encoder(obj: Any) -> Any:
    """Convert objects to JSON-serializable forms for cache keys."""
    if obj is None or isinstance(obj, (bool, int, float, str)):
        return obj
    if isinstance(obj, (list, tuple)):
        return [safe_jsonable_encoder(item) for item in obj]
    if isinstance(obj, dict):
        return {str(k): safe_jsonable_encoder(v) for k, v in obj.items()}
    if isinstance(obj, set):
        return sorted([safe_jsonable_encoder(item) for item in obj])
    if isinstance(obj, bytes):
        return obj.decode("utf-8", errors="ignore")
    try:
        import arrow

        if isinstance(obj, arrow.Arrow):
            return obj.isoformat()
    except ImportError:
        pass
    try:
        from datetime import date, datetime, time

        if isinstance(obj, (datetime, date, time)):
            return obj.isoformat()
    except ImportError:
        pass
    try:
        from pathlib import Path

        if isinstance(obj, Path):
            return str(obj)
    except ImportError:
        pass
    if BaseModel is not None and isinstance(obj, BaseModel):
        return obj.model_dump()
    if hasattr(obj, "__dict__"):
        return safe_jsonable_encoder(obj.__dict__)
    return str(obj)


def _is_basemodel_class(cls: Any) -> bool:
    return BaseModel is not None and isinstance(cls, type) and issubclass(cls, BaseModel)


def _model_info(annotation: Any) -> tuple[type | None, str]:
    """Return `(Model class, container)` extracted from a return annotation.

    `container` is one of `"none"` (single value), `"list"`, or `"dict"`.
    Returns `(None, "none")` when no BaseModel is in play (decorator falls back
    to pass-through encode/decode).
    """
    if BaseModel is None or annotation is inspect.Parameter.empty or annotation is None:
        return None, "none"
    if _is_basemodel_class(annotation):
        return annotation, "none"

    origin = typing.get_origin(annotation)
    if origin in (Union, types.UnionType):
        for arg in typing.get_args(annotation):
            if _is_basemodel_class(arg):
                return arg, "none"
        return None, "none"
    if origin is list:
        args = typing.get_args(annotation)
        if args and _is_basemodel_class(args[0]):
            return args[0], "list"
    if origin is dict:
        args = typing.get_args(annotation)
        if len(args) == 2 and _is_basemodel_class(args[1]):
            return args[1], "dict"
    return None, "none"


def _encode(value: Any, model_cls: type | None, container: str) -> Any:
    """Convert pydantic models to plain dicts before pickling."""
    if value is None or model_cls is None:
        return value
    if container == "list":
        return [v.model_dump() if isinstance(v, model_cls) else v for v in value]
    if container == "dict":
        return {k: (v.model_dump() if isinstance(v, model_cls) else v) for k, v in value.items()}
    if isinstance(value, model_cls):
        return value.model_dump()
    return value


def _decode(value: Any, model_cls: type | None, container: str) -> Any:
    """Rehydrate dicts into pydantic models on cache hit."""
    if value is None or model_cls is None:
        return value
    if container == "list":
        return [model_cls.model_validate(v) if isinstance(v, dict) else v for v in value]
    if container == "dict":
        return {k: (model_cls.model_validate(v) if isinstance(v, dict) else v) for k, v in value.items()}
    if isinstance(value, dict):
        return model_cls.model_validate(value)
    return value


def cached(
    cache: diskcache.Cache | None = None,
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    """Disk-backed memoization decorator.

    Detects `BaseModel` / `list[Model]` / `dict[str, Model]` return annotations
    and stores them as dicts (rehydrated on read) so model classes defined in
    `__main__` round-trip across script invocations.
    """
    if cache is None:
        cache = diskcache.Cache()

    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        func_source = inspect.getsource(func)
        func_hash = hashlib.md5(func_source.encode()).hexdigest()
        try:
            return_anno = inspect.signature(func).return_annotation
        except (TypeError, ValueError):
            return_anno = inspect.Parameter.empty
        model_cls, container = _model_info(return_anno)

        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> T:
            json_args = [safe_jsonable_encoder(arg) for arg in args]
            json_kwargs = {k: safe_jsonable_encoder(v) for k, v in kwargs.items()}
            arg_hash = hashlib.md5(
                f"{json.dumps(json_args)}{json.dumps(json_kwargs)}".encode()
            ).hexdigest()
            key: str = hashlib.md5(
                f"{func.__name__}{func_hash}{arg_hash}".encode()
            ).hexdigest()

            raw = cache.get(key, default=_MISSING)
            if raw is not _MISSING:
                decoded = _decode(raw, model_cls, container)
                if asyncio.iscoroutinefunction(func):

                    async def return_cached():
                        return decoded

                    return return_cached()  # type: ignore[return-value]
                return decoded  # type: ignore[return-value]

            if asyncio.iscoroutinefunction(func):

                async def execute():
                    result = await func(*args, **kwargs)  # type: ignore[misc]
                    cache.set(key, _encode(result, model_cls, container))
                    return result

                return execute()  # type: ignore[return-value]

            result = func(*args, **kwargs)
            cache.set(key, _encode(result, model_cls, container))
            return result

        return wrapper

    return decorator
