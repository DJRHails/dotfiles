#!/usr/bin/env python3
"""Search Claude Code session history by keyword.

Usage:
    session-search <query> [--project <path>] [--context <n>] [--limit <n>]

Examples:
    session-search "yard definition"
    session-search "margin notes" --project hails.info
    session-search "LoRA" --context 300 --limit 5
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

AGENTS_DIR = Path.home() / ".agents"
CLAUDE_DIR = Path.home() / ".claude"

HISTORY_PATHS = [
    AGENTS_DIR / "history.jsonl",
    CLAUDE_DIR / "history.jsonl",
]

PROJECTS_DIRS = [
    AGENTS_DIR / "projects",
    CLAUDE_DIR / "projects",
]

_UUID_RE = re.compile(
    r"""(?x)
    ^[0-9a-f]{8}
    -[0-9a-f]{4}
    -[0-9a-f]{4}
    -[0-9a-f]{4}
    -[0-9a-f]{12}$
    """
)


def _read_jsonl(path):
    """Yield parsed JSON objects from a JSONL file, skipping bad lines."""
    if not path.exists():
        return
    with open(path) as f:
        for line in f:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def load_history_index():
    """Build a map of sessionId -> {display, timestamp, project}."""
    index = {}
    for path in HISTORY_PATHS:
        for entry in _read_jsonl(path):
            sid = entry.get("sessionId")
            if not sid:
                continue
            index[sid] = {
                "display": entry.get("display", ""),
                "timestamp": entry.get("timestamp", 0),
                "project": entry.get("project", ""),
            }
    return index


def find_session_files(project_filter=None):
    """Yield (session_id, path) for all session JSONL files."""
    for projects_dir in PROJECTS_DIRS:
        if not projects_dir.exists():
            continue
        for proj_dir in projects_dir.iterdir():
            if not proj_dir.is_dir():
                continue
            if project_filter and project_filter not in proj_dir.name:
                continue
            for jsonl in proj_dir.glob("*.jsonl"):
                if not _UUID_RE.match(jsonl.stem):
                    continue
                yield jsonl.stem, jsonl


def _extract_message_texts(msg):
    """Yield (role, text) pairs from a message dict."""
    if not isinstance(msg, dict):
        return
    role = msg.get("role", "?")
    content = msg.get("content", "")
    if isinstance(content, str):
        yield role, content
        return
    if not isinstance(content, list):
        return
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") != "text":
            continue
        yield role, block.get("text", "")


def extract_text_blocks(obj):
    """Extract all text content from a session JSONL line."""
    if not isinstance(obj, dict):
        return
    msg = obj.get("message", {})
    yield from _extract_message_texts(msg)
    top_content = obj.get("content", "")
    if isinstance(top_content, str) and top_content:
        yield "system", top_content


def _make_snippet(text, idx, context_chars):
    """Extract a snippet around idx with context."""
    start = max(0, idx - context_chars)
    end = min(len(text), idx + context_chars)
    snippet = text[start:end].strip()
    if start > 0:
        snippet = "..." + snippet
    if end < len(text):
        snippet = snippet + "..."
    return snippet


def search_session(path, terms, context_chars=200):
    """Search a session file for lines matching all terms."""
    matches = []
    lower_terms = [t.lower() for t in terms]
    with open(path) as f:
        for line_num, line in enumerate(f):
            if not all(t in line.lower() for t in lower_terms):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            for role, text in extract_text_blocks(obj):
                low_text = text.lower()
                if not all(t in low_text for t in lower_terms):
                    continue
                idx = low_text.find(lower_terms[0])
                matches.append({
                    "line": line_num,
                    "role": role,
                    "snippet": _make_snippet(text, idx, context_chars),
                })
    return matches


def format_timestamp(ts_ms):
    """Convert millisecond timestamp to human-readable date."""
    if not ts_ms:
        return "unknown date"
    dt = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M UTC")


def _print_session(result):
    """Print a single session result."""
    ts = format_timestamp(result["timestamp"])
    proj = result["project"].split("/")[-1] if result["project"] else "unknown"
    print(f"\n{'=' * 72}")
    print(f"Session:  {result['session_id']}")
    print(f"Date:     {ts}")
    print(f"Project:  {proj}")
    print(f"Prompt:   {result['display'][:120]}")
    print(f"Resume:   claude --resume {result['session_id']}")
    print(f"Matches:  {len(result['matches'])}")
    for m in result["matches"][:3]:
        print(f"\n  [{m['role']}] (line {m['line']}):")
        lines = m["snippet"].split("\n")[:6]
        for snippet_line in lines:
            print(f"    {snippet_line}")
        if len(m["snippet"].split("\n")) > 6:
            print("    ...")
    if len(result["matches"]) > 3:
        print(f"\n  ... and {len(result['matches']) - 3} more matches")


def main():
    parser = argparse.ArgumentParser(
        description="Search Claude Code session history"
    )
    parser.add_argument(
        "query",
        help="Search terms (space-separated, all must match)",
    )
    parser.add_argument(
        "--project",
        help="Filter to project directories containing this string",
    )
    parser.add_argument(
        "--context",
        type=int,
        default=200,
        help="Characters of context around match (default: 200)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Max sessions to show (default: 10)",
    )
    args = parser.parse_args()

    terms = args.query.split()
    if not terms:
        print("No search terms provided.", file=sys.stderr)
        sys.exit(1)

    history = load_history_index()
    results = []

    for session_id, path in find_session_files(args.project):
        matches = search_session(path, terms, args.context)
        if not matches:
            continue
        info = history.get(session_id, {})
        results.append({
            "session_id": session_id,
            "path": str(path),
            "display": info.get("display", "(no prompt recorded)"),
            "timestamp": info.get("timestamp", 0),
            "project": info.get("project", ""),
            "matches": matches,
        })

    results.sort(key=lambda r: r["timestamp"], reverse=True)

    if not results:
        print(f"No sessions found matching: {args.query}")
        sys.exit(0)

    for r in results[:args.limit]:
        _print_session(r)

    remaining = len(results) - args.limit
    if remaining > 0:
        print(f"\n... and {remaining} more sessions (use --limit to see more)")

    print(f"\n{'=' * 72}")
    print(f"Total: {len(results)} sessions matched")


if __name__ == "__main__":
    main()
