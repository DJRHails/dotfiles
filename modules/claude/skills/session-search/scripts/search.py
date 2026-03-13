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
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

CLAUDE_DIR = Path.home() / ".agents"
HISTORY_PATH = CLAUDE_DIR / "history.jsonl"
PROJECTS_DIR = CLAUDE_DIR / "projects"


def load_history_index():
    """Build a map of sessionId -> {display, timestamp, project}."""
    index = {}
    if not HISTORY_PATH.exists():
        return index
    with open(HISTORY_PATH) as f:
        for line in f:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            sid = entry.get("sessionId")
            if sid:
                index[sid] = {
                    "display": entry.get("display", ""),
                    "timestamp": entry.get("timestamp", 0),
                    "project": entry.get("project", ""),
                }
    return index


def find_session_files(project_filter=None):
    """Yield (session_id, path) for all session JSONL files."""
    if not PROJECTS_DIR.exists():
        return
    for proj_dir in PROJECTS_DIR.iterdir():
        if not proj_dir.is_dir():
            continue
        if project_filter and project_filter not in proj_dir.name:
            continue
        for jsonl in proj_dir.glob("*.jsonl"):
            stem = jsonl.stem
            # Session files are UUIDs at the top level
            if re.match(
                r"""(?x)
                ^[0-9a-f]{8}
                -[0-9a-f]{4}
                -[0-9a-f]{4}
                -[0-9a-f]{4}
                -[0-9a-f]{12}$
                """,
                stem,
            ):
                yield stem, jsonl


def extract_text_blocks(obj):
    """Extract all text content from a session JSONL line."""
    if not isinstance(obj, dict):
        return
    msg = obj.get("message", {})
    if isinstance(msg, dict):
        content = msg.get("content", "")
        if isinstance(content, str):
            yield obj.get("message", {}).get("role", "?"), content
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    yield msg.get("role", "?"), block.get("text", "")
    # Some entries store content at the top level (system messages)
    top_content = obj.get("content", "")
    if isinstance(top_content, str) and top_content:
        yield "system", top_content


def search_session(path, terms, context_chars=200):
    """Search a session file for lines matching all terms. Return matches."""
    matches = []
    lower_terms = [t.lower() for t in terms]
    with open(path) as f:
        for line_num, line in enumerate(f):
            low = line.lower()
            if not all(t in low for t in lower_terms):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            for role, text in extract_text_blocks(obj):
                low_text = text.lower()
                if not all(t in low_text for t in lower_terms):
                    continue
                # Find best match position (near first term)
                idx = low_text.find(lower_terms[0])
                start = max(0, idx - context_chars)
                end = min(len(text), idx + context_chars)
                snippet = text[start:end].strip()
                if start > 0:
                    snippet = "..." + snippet
                if end < len(text):
                    snippet = snippet + "..."
                matches.append({
                    "line": line_num,
                    "role": role,
                    "snippet": snippet,
                })
    return matches


def format_timestamp(ts_ms):
    """Convert millisecond timestamp to human-readable date."""
    if not ts_ms:
        return "unknown date"
    dt = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M UTC")


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
        if matches:
            info = history.get(session_id, {})
            results.append({
                "session_id": session_id,
                "path": str(path),
                "display": info.get("display", "(no prompt recorded)"),
                "timestamp": info.get("timestamp", 0),
                "project": info.get("project", ""),
                "matches": matches,
            })

    # Sort by timestamp descending (most recent first)
    results.sort(key=lambda r: r["timestamp"], reverse=True)

    if not results:
        print(f"No sessions found matching: {args.query}")
        sys.exit(0)

    shown = 0
    for r in results:
        if shown >= args.limit:
            remaining = len(results) - shown
            print(f"\n... and {remaining} more sessions (use --limit to see more)")
            break
        shown += 1
        ts = format_timestamp(r["timestamp"])
        proj = r["project"].split("/")[-1] if r["project"] else "unknown"
        print(f"\n{'=' * 72}")
        print(f"Session:  {r['session_id']}")
        print(f"Date:     {ts}")
        print(f"Project:  {proj}")
        print(f"Prompt:   {r['display'][:120]}")
        print(f"Resume:   claude --resume {r['session_id']}")
        print(f"Matches:  {len(r['matches'])}")
        for m in r["matches"][:3]:
            print(f"\n  [{m['role']}] (line {m['line']}):")
            # Indent snippet
            for snippet_line in m["snippet"].split("\n")[:6]:
                print(f"    {snippet_line}")
            if len(m["snippet"].split("\n")) > 6:
                print("    ...")
        if len(r["matches"]) > 3:
            print(f"\n  ... and {len(r['matches']) - 3} more matches")

    print(f"\n{'=' * 72}")
    print(f"Total: {len(results)} sessions matched")


if __name__ == "__main__":
    main()
