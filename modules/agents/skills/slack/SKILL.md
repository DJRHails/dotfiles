---
name: slack
description: Search Slack files / messages / users and download files by ID using the user's browser session — no per-workspace bot token setup. Auto-discovers xoxc tokens from Chromium localStorage. Use when the user references a Slack file ID (e.g. F0A8SHNBR2N), wants to find a file or message in Slack, needs to resolve a person's display name to their @handle, or wants to download a Slack attachment.
---

# Slack CLI

Reads Slack via the unofficial web API using xoxc workspace tokens auto-extracted from Chromium localStorage (via `chromium-reader`) + `d` cookie from the browser. Works against Enterprise Grid workspaces (Anthropic, Constellation/astra-fellowship, etc.) where bot tokens require admin install.

## Prerequisites

- User signed into Slack web (`https://app.slack.com/`) in a Chromium-family browser (Arc default; also Chrome, Brave, Edge, Chromium). Firefox/Safari supported for cookies only — auto-discovery needs Chromium localStorage.
- `uv` installed — PEP 723 deps include `browser-cookie3`, `chromium-reader`, `diskcache`, `pydantic`, `requests`, `rich`, `typer`.

## Commands

All commands use `slack.py` from this skill dir. Default browser is Arc; override with `-b chrome|brave|edge|chromium|firefox|safari`. Top-level `-v` / `--verbose` exposes auto-discovery details on stderr.

### Files

```bash
./slack.py files info <FILE_ID>           # metadata + download URL
./slack.py files download <FILE_ID>       # save to file's own name in cwd
./slack.py files download <FILE_ID> -o /path/out.md
./slack.py files search "<query>"         # Slack syntax: 'filename:*.md', 'from:@handle', 'in:#chan'
```

### Messages

```bash
./slack.py messages search "<query>"      # 'from:@handle slurm', 'in:#fellows-tech-support-chatter', 'has:link'
```

### Users — resolve display name to @handle

```bash
./slack.py users search "<substring>"     # matches against handle / real name / display name / email
```

Slack's `from:@<handle>` filter needs the exact username, not the display name. Use `users search` to look it up. The paginated `users.list` is cached daily.

### Bootstrap (rarely needed — auto-discovery usually works)

```bash
./slack.py bootstrap                      # capture xoxc from clipboard or stdin → ~/.config/slack/token
```

Only needed if the user isn't signed into a Chromium browser. In any logged-in Slack web tab → DevTools Console → `copy(TS.boot_data.api_token)`, then run `bootstrap`.

## Auth

Token resolution order:
1. `$SLACK_TOKEN` env (or `$SLACK_XOXC_TOKEN`)
2. `~/.config/slack/token`
3. **Auto-discovery**: scan all Chromium browser profile leveldb stores for xoxc tokens, validate each against `auth.test`, pick the first that works. Multi-workspace users get correct routing.

Workspace resolution: derived from the validated token's `auth.test` URL. Override with `$SLACK_WORKSPACE`.

## When to use this skill

- **Use** when:
  - The user references a Slack file ID (`F0A8SHNBR2N` format)
  - "Find this in Slack" / "what did so-and-so say about X" / "download that attachment"
  - The user wants to look up a Slack handle for someone they only know by display name
- **Don't use** for actions that send/post in Slack — this CLI is read-only.

## Examples

```bash
# Download Faizan's RunPod guide attached to a Slack message
./slack.py files download F0A8SHNBR2N -o RUNPOD_INFRASTRUCTURE_GUIDE.md

# Resolve "faizan" → @faizanali619 before searching for messages
./slack.py users search faizan
# → @faizanali619  Faizan Ali  (faizan)  Anthropic Fellow  U09MQ1LP269

# Find messages from that user about slurm
./slack.py messages search 'from:@faizanali619 slurm' -n 5

# Search files for the runpod guide
./slack.py files search 'RUNPOD_INFRASTRUCTURE' -n 3
```

## Caching

Responses memoized to `/tmp/slack-cli-{YYYY-MM-DD}` (rolls daily). The heavyweight `users.list` pagination (hundreds of members across multiple pages) and `auth.test` token-probing dominate uncached time; both are cached after first run. Pydantic models round-trip via [`emboss`](https://pypi.org/project/emboss/)'s `model_dump`/`model_validate`.

## Gotchas

- **Multiple Slack accounts**: with 3+ profiles signed into different workspaces, auto-discovery validates each token and picks one that works. `-v` shows which workspace was selected. Use `$SLACK_WORKSPACE` to pin.
- **Enterprise Grid quirks**: the `search.modules.users` and `users.search` typeahead endpoints return `unknown_method` for xoxc — that's why `users search` falls back to paginating `users.list`. Slower (~5s on first run) but reliable.
- **Slack `from:` filter is case-sensitive on handle**: `from:@FaizanAli619` ≠ `from:@faizanali619`. `users search` output gives the right casing.

## Local files

- `slack.py` — the CLI (PEP 723 inline deps, runs via `uv run`)
