---
name: session-search
description: Search previous Claude Code session history by keyword. Use when the user asks to find a past conversation, recall what was discussed, or locate a session where a topic came up.
---

# Session Search

Search across all Claude Code session transcripts (`~/.claude/`, `~/.agents/`) and Pi agent sessions (`~/.pi/agent/sessions/`), including Pi artifacts (plans, context docs, etc.).

## When to use

- User asks "which session did we talk about X?"
- User wants to find a previous conversation by topic
- User needs to recall advice, code, or decisions from past sessions

## Usage

Run the helper script with a quoted search query:

```bash
python3 ~/.claude/skills/session-search/scripts/search.py "your search terms"
```

All terms must appear in the same text block for a match (AND logic).

### Options

| Flag | Default | Purpose |
|------|---------|---------|
| `--project <str>` | all | Filter to project dirs containing this string |
| `--context <n>` | 200 | Characters of context around each match |
| `--limit <n>` | 10 | Max sessions to display |

### Examples

```bash
# Find sessions discussing margin notes
python3 ~/.claude/skills/session-search/scripts/search.py "margin notes"

# Narrow to a specific project
python3 ~/.claude/skills/session-search/scripts/search.py "LoRA" --project kb

# More context, more results
python3 ~/.claude/skills/session-search/scripts/search.py "deploy" --context 400 --limit 20
```

## Output

For each matching session the script prints:

- **Session ID** and resume command (`claude --resume <id>`)
- **Date**, **project**, and the **original prompt**
- Up to 3 **matching snippets** with role labels and line numbers

## Notes

- Searches `~/.claude/projects/`, `~/.agents/projects/`, and `~/.pi/agent/sessions/` for session transcripts
- History index from both `~/.claude/history.jsonl` and `~/.agents/history.jsonl`
- Pi sessions are identified with `[pi]` label and show the file path instead of a resume command
- Pi artifacts (markdown files under `artifacts/`) are also searched and labelled `(pi artifact: <name>)`
- Searches text content from user and assistant messages (skips tool calls, binary data, etc.)
- Subagent files are not searched (only top-level session files)
