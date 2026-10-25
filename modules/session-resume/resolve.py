#!/usr/bin/env python3
"""Resolve a Claude/Codex UUID prefix without guessing across session stores."""

import json
import os
import re
import sys
from pathlib import Path


def resolve(target: str, prefix: str) -> dict[str, str]:
    if not re.fullmatch(r"[0-9a-fA-F-]{4,36}", prefix):
        raise ValueError("expected a session UUID or a prefix of at least four characters")
    prefix = prefix.lower()
    home = Path.home()
    codex_home = Path(os.environ.get("CODEX_HOME") or home / ".codex")
    claude_home = Path(os.environ.get("CLAUDE_CONFIG_DIR") or home / ".claude")
    roots = {claude_home, home / ".claude", home / ".claude-ant", home / ".agents"}
    matches: list[tuple[str, str, Path, Path]] = []
    for root in roots:
        for file in (root / "projects").glob(f"*/{prefix}*.jsonl"):
            matches.append((file.stem, "claude", file, root))
    for store in ("sessions", "archived_sessions"):
        for file in (codex_home / store).rglob(f"*{prefix}*.jsonl"):
            match = re.search(r"([0-9a-f-]{36})\.jsonl$", file.name)
            if match and match[1].startswith(prefix):
                matches.append((match[1], "codex", file, codex_home))
    ids = sorted({item[0] for item in matches})
    if not ids:
        raise ValueError(f"no session '{prefix}' under Claude or Codex session stores")
    if len(ids) > 1:
        raise ValueError(f"'{prefix}' is ambiguous — it prefixes {len(ids)} sessions:\n  " + "\n  ".join(ids))
    # Once converted, resume the target's continued history instead of overwriting it.
    native = [item for item in matches if item[1] == target]
    _, source, file, root = max(native or matches, key=lambda item: item[2].stat().st_mtime_ns)
    cwd = ""
    with file.open() as transcript:
        for line in transcript:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue  # An active session can end with a partial record.
            if source == "codex":
                if record.get("type") == "session_meta":
                    cwd = record.get("payload", {}).get("cwd", "")
            else:
                cwd = record.get("cwd", "")
            if cwd:
                break
    if not cwd or not Path(cwd).is_dir():
        raise ValueError(f"cannot resolve cwd for '{ids[0]}' ({file})")
    return {
        "id": ids[0], "source": source, "file": str(file), "cwd": cwd,
        "claude_home": str(root if source == "claude" else claude_home),
        "codex_home": str(codex_home),
    }


if __name__ == "__main__":
    try:
        print(json.dumps(resolve(sys.argv[1], sys.argv[2])))
    except (ValueError, OSError) as error:
        print(f"{sys.argv[1]}::resume: {error}", file=sys.stderr)
        sys.exit(1)
