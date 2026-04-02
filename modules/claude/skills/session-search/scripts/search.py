#!/usr/bin/env python3
"""Search Claude Code and Pi session history by keyword.

Usage:
    session-search <query> [--project <path>] [--context <n>] [--limit <n>]

Examples:
    session-search "yard definition"
    session-search "margin notes" --project hails.info
    session-search "LoRA" --context 300 --limit 5
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

AGENTS_DIR = Path.home() / ".agents"
CLAUDE_DIR = Path.home() / ".claude"
PI_DIR = Path.home() / ".pi"

HISTORY_PATHS = [
    AGENTS_DIR / "history.jsonl",
    CLAUDE_DIR / "history.jsonl",
]

PROJECTS_DIRS = [
    AGENTS_DIR / "projects",
    CLAUDE_DIR / "projects",
]

PI_SESSIONS_DIR = PI_DIR / "agent" / "sessions"

MAX_SNIPPET_LINES = 6
MAX_DISPLAYED_MATCHES = 3

_UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

_TEXT_BLOCK_TYPES = frozenset(("text", "thinking"))


# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


class SessionSource(Enum):
    CLAUDE = "claude"
    PI = "pi"
    PI_ARTIFACT = "pi-artifact"


@dataclass(kw_only=True, frozen=True)
class SessionFile:
    file_id: str
    path: Path
    source: SessionSource


@dataclass(kw_only=True, frozen=True)
class MatchSnippet:
    line: int
    role: str
    snippet: str


@dataclass(kw_only=True, frozen=True)
class HistoryEntry:
    display: str = ""
    timestamp_ms: int = 0
    project: str = ""


@dataclass(kw_only=True, frozen=True)
class PiSessionHeader:
    session_id: str = ""
    timestamp_iso: str = ""
    cwd: str = ""


@dataclass(kw_only=True, frozen=True)
class SearchResult:
    session_id: str
    path: Path
    display: str
    timestamp_ms: int
    project: str
    source: SessionSource
    matches: tuple[MatchSnippet, ...] = ()


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------


def _read_jsonl(path: Path) -> Iterator[dict[str, Any]]:
    if not path.exists():
        return
    with open(path) as f:
        for line in f:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def _iso_to_ms(iso: str) -> int:
    if not iso:
        return 0
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return int(dt.timestamp() * 1000)
    except (ValueError, AttributeError):
        return 0


def _mtime_ms(path: Path) -> int:
    try:
        return int(path.stat().st_mtime * 1000)
    except OSError:
        return 0


def _matches_filter(name: str, project_filter: str | None) -> bool:
    if not project_filter:
        return True
    return project_filter in name


# ---------------------------------------------------------------------------
# History index
# ---------------------------------------------------------------------------


def load_history_index() -> dict[str, HistoryEntry]:
    index: dict[str, HistoryEntry] = {}
    for path in HISTORY_PATHS:
        for entry in _read_jsonl(path):
            sid = entry.get("sessionId")
            if not sid:
                continue
            index[sid] = HistoryEntry(
                display=entry.get("display", ""),
                timestamp_ms=entry.get("timestamp", 0),
                project=entry.get("project", ""),
            )
    return index


# ---------------------------------------------------------------------------
# File discovery — one generator per source, composed at the top
# ---------------------------------------------------------------------------


def _discover_claude_sessions(project_filter: str | None) -> Iterator[SessionFile]:
    for projects_dir in PROJECTS_DIRS:
        if not projects_dir.exists():
            continue
        for proj_dir in projects_dir.iterdir():
            if not proj_dir.is_dir():
                continue
            if not _matches_filter(proj_dir.name, project_filter):
                continue
            for jsonl in proj_dir.glob("*.jsonl"):
                if _UUID_RE.match(jsonl.stem):
                    yield SessionFile(file_id=jsonl.stem, path=jsonl, source=SessionSource.CLAUDE)


def _discover_pi_sessions(project_filter: str | None) -> Iterator[SessionFile]:
    if not PI_SESSIONS_DIR.exists():
        return
    for proj_dir in PI_SESSIONS_DIR.iterdir():
        if not proj_dir.is_dir():
            continue
        if not _matches_filter(proj_dir.name, project_filter):
            continue
        for jsonl in proj_dir.glob("*.jsonl"):
            yield SessionFile(file_id=jsonl.stem, path=jsonl, source=SessionSource.PI)


def _discover_pi_artifacts(project_filter: str | None) -> Iterator[SessionFile]:
    if not PI_SESSIONS_DIR.exists():
        return
    for proj_dir in PI_SESSIONS_DIR.iterdir():
        if not proj_dir.is_dir():
            continue
        if not _matches_filter(proj_dir.name, project_filter):
            continue
        artifacts_dir = proj_dir / "artifacts"
        if not artifacts_dir.exists():
            continue
        for md in artifacts_dir.rglob("*.md"):
            yield SessionFile(file_id=md.stem, path=md, source=SessionSource.PI_ARTIFACT)


def find_session_files(project_filter: str | None = None) -> list[SessionFile]:
    return [
        *_discover_claude_sessions(project_filter),
        *_discover_pi_sessions(project_filter),
        *_discover_pi_artifacts(project_filter),
    ]


# ---------------------------------------------------------------------------
# Text extraction
# ---------------------------------------------------------------------------


def _text_from_content_block(block: dict[str, Any]) -> str:
    if block.get("type") not in _TEXT_BLOCK_TYPES:
        return ""
    return block.get("text", "") or block.get("thinking", "")


def _extract_message_texts(msg: dict[str, Any]) -> list[tuple[str, str]]:
    if not isinstance(msg, dict):
        return []

    role: str = msg.get("role", "?")
    content = msg.get("content", "")

    # Simple string content
    if isinstance(content, str):
        return [(role, content)]

    # Array of content blocks
    if not isinstance(content, list):
        return []

    return [
        (role, text)
        for block in content
        if isinstance(block, dict) and (text := _text_from_content_block(block))
    ]


def _extract_text_blocks_claude(obj: dict[str, Any]) -> list[tuple[str, str]]:
    pairs = _extract_message_texts(obj.get("message", {}))
    top_content = obj.get("content", "")
    if isinstance(top_content, str) and top_content:
        pairs.append(("system", top_content))
    return pairs


def _extract_text_blocks_pi(obj: dict[str, Any]) -> list[tuple[str, str]]:
    if obj.get("type") != "message":
        return []
    return _extract_message_texts(obj.get("message", {}))


_TEXT_EXTRACTORS = {
    SessionSource.CLAUDE: _extract_text_blocks_claude,
    SessionSource.PI: _extract_text_blocks_pi,
}


def extract_text_blocks(obj: dict[str, Any], source: SessionSource) -> list[tuple[str, str]]:
    extractor = _TEXT_EXTRACTORS.get(source)
    if not extractor:
        return []
    return extractor(obj)


# ---------------------------------------------------------------------------
# Snippet
# ---------------------------------------------------------------------------


def _make_snippet(text: str, idx: int, context_chars: int) -> str:
    start = max(0, idx - context_chars)
    end = min(len(text), idx + context_chars)
    snippet = text[start:end].strip()
    if start > 0:
        snippet = "..." + snippet
    if end < len(text):
        snippet = snippet + "..."
    return snippet


# ---------------------------------------------------------------------------
# Term matching
# ---------------------------------------------------------------------------


def _all_terms_present(text: str, lower_terms: Sequence[str]) -> bool:
    return all(t in text for t in lower_terms)


def _find_matches_in_line(
    line_num: int,
    obj: dict[str, Any],
    source: SessionSource,
    lower_terms: Sequence[str],
    context_chars: int,
) -> list[MatchSnippet]:
    hits: list[MatchSnippet] = []
    for role, text in extract_text_blocks(obj, source):
        low_text = text.lower()
        if not _all_terms_present(low_text, lower_terms):
            continue
        idx = low_text.find(lower_terms[0])
        hits.append(MatchSnippet(
            line=line_num,
            role=role,
            snippet=_make_snippet(text, idx, context_chars),
        ))
    return hits


# ---------------------------------------------------------------------------
# Searching
# ---------------------------------------------------------------------------


def _search_artifact(path: Path, lower_terms: Sequence[str], context_chars: int) -> list[MatchSnippet]:
    try:
        text = path.read_text()
    except OSError:
        return []
    low_text = text.lower()
    if not _all_terms_present(low_text, lower_terms):
        return []
    idx = low_text.find(lower_terms[0])
    return [MatchSnippet(line=0, role="artifact", snippet=_make_snippet(text, idx, context_chars))]


def _search_jsonl(sf: SessionFile, lower_terms: Sequence[str], context_chars: int) -> list[MatchSnippet]:
    matches: list[MatchSnippet] = []
    with open(sf.path) as f:
        for line_num, raw_line in enumerate(f):
            if not _all_terms_present(raw_line.lower(), lower_terms):
                continue
            try:
                obj = json.loads(raw_line)
            except json.JSONDecodeError:
                continue
            matches.extend(_find_matches_in_line(line_num, obj, sf.source, lower_terms, context_chars))
    return matches


def search_session(sf: SessionFile, terms: Sequence[str], context_chars: int) -> list[MatchSnippet]:
    lower_terms = [t.lower() for t in terms]
    if sf.source == SessionSource.PI_ARTIFACT:
        return _search_artifact(sf.path, lower_terms, context_chars)
    return _search_jsonl(sf, lower_terms, context_chars)


# ---------------------------------------------------------------------------
# Pi session header
# ---------------------------------------------------------------------------


def extract_pi_session_header(path: Path) -> PiSessionHeader:
    try:
        with open(path) as f:
            for line in f:
                obj = json.loads(line)
                if obj.get("type") == "session":
                    return PiSessionHeader(
                        session_id=obj.get("id", ""),
                        timestamp_iso=obj.get("timestamp", ""),
                        cwd=obj.get("cwd", ""),
                    )
    except (json.JSONDecodeError, OSError):
        pass
    return PiSessionHeader()


# ---------------------------------------------------------------------------
# Result building — one builder per source
# ---------------------------------------------------------------------------


def _build_pi_result(sf: SessionFile, matches: tuple[MatchSnippet, ...]) -> SearchResult:
    header = extract_pi_session_header(sf.path)
    return SearchResult(
        session_id=header.session_id or sf.file_id,
        path=sf.path,
        display="(pi session)",
        timestamp_ms=_iso_to_ms(header.timestamp_iso),
        project=header.cwd or sf.path.parent.name,
        source=sf.source,
        matches=matches,
    )


def _build_artifact_result(sf: SessionFile, matches: tuple[MatchSnippet, ...]) -> SearchResult:
    # artifacts/<session-id>/subdir/file.md
    return SearchResult(
        session_id=sf.path.parent.parent.name,
        path=sf.path,
        display=f"(pi artifact: {sf.path.name})",
        timestamp_ms=_mtime_ms(sf.path),
        project=sf.path.parents[3].name,
        source=sf.source,
        matches=matches,
    )


def _build_claude_result(
    sf: SessionFile, matches: tuple[MatchSnippet, ...], history: dict[str, HistoryEntry],
) -> SearchResult:
    entry = history.get(sf.file_id, HistoryEntry())
    return SearchResult(
        session_id=sf.file_id,
        path=sf.path,
        display=entry.display or "(no prompt recorded)",
        timestamp_ms=entry.timestamp_ms,
        project=entry.project,
        source=SessionSource.CLAUDE,
        matches=matches,
    )


def build_result(
    sf: SessionFile,
    matches: Sequence[MatchSnippet],
    history: dict[str, HistoryEntry],
) -> SearchResult:
    match_tuple = tuple(matches)
    if sf.source == SessionSource.PI:
        return _build_pi_result(sf, match_tuple)
    if sf.source == SessionSource.PI_ARTIFACT:
        return _build_artifact_result(sf, match_tuple)
    return _build_claude_result(sf, match_tuple, history)


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------


def format_timestamp(ts_ms: int) -> str:
    if not ts_ms:
        return "unknown date"
    dt = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M UTC")


def _format_location(result: SearchResult) -> str:
    if result.source in (SessionSource.PI, SessionSource.PI_ARTIFACT):
        return f"File:     {result.path}"
    return f"Resume:   claude --resume {result.session_id}"


def _format_snippet(m: MatchSnippet) -> str:
    lines = m.snippet.split("\n")[:MAX_SNIPPET_LINES]
    body = "\n".join(f"    {line}" for line in lines)
    if len(m.snippet.split("\n")) > MAX_SNIPPET_LINES:
        body += "\n    ..."
    return f"\n  [{m.role}] (line {m.line}):\n{body}"


def print_result(result: SearchResult) -> None:
    ts = format_timestamp(result.timestamp_ms)
    proj = result.project.rsplit("/", 1)[-1] if result.project else "unknown"
    source_label = " [pi]" if result.source == SessionSource.PI else ""

    print(f"\n{'=' * 72}")
    print(f"Session:  {result.session_id}{source_label}")
    print(f"Date:     {ts}")
    print(f"Project:  {proj}")
    print(f"Prompt:   {result.display[:120]}")
    print(_format_location(result))
    print(f"Matches:  {len(result.matches)}")

    for m in result.matches[:MAX_DISPLAYED_MATCHES]:
        print(_format_snippet(m))

    overflow = len(result.matches) - MAX_DISPLAYED_MATCHES
    if overflow > 0:
        print(f"\n  ... and {overflow} more matches")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description="Search Claude Code and Pi session history")
    parser.add_argument("query", help="Search terms (space-separated, all must match)")
    parser.add_argument("--project", help="Filter to project directories containing this string")
    parser.add_argument("--context", type=int, default=200, help="Characters of context around match (default: 200)")
    parser.add_argument("--limit", type=int, default=10, help="Max sessions to show (default: 10)")
    args = parser.parse_args()

    terms: list[str] = args.query.split()
    if not terms:
        print("No search terms provided.", file=sys.stderr)
        sys.exit(1)

    history = load_history_index()
    results: list[SearchResult] = [
        build_result(sf, matches, history)
        for sf in find_session_files(args.project)
        if (matches := search_session(sf, terms, args.context))
    ]
    results.sort(key=lambda r: r.timestamp_ms, reverse=True)

    if not results:
        print(f"No sessions found matching: {args.query}")
        sys.exit(0)

    for r in results[: args.limit]:
        print_result(r)

    overflow = len(results) - args.limit
    if overflow > 0:
        print(f"\n... and {overflow} more sessions (use --limit to see more)")

    print(f"\n{'=' * 72}")
    print(f"Total: {len(results)} sessions matched")


if __name__ == "__main__":
    main()
