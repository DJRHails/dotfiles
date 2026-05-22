---
name: notion
description: Fetch Notion pages as Markdown from the CLI using your existing browser session cookies — no per-page integration grants. Search workspaces, list logged-in identities across browser profiles. Use when the user references a Notion page URL/ID, says "import this Notion page", asks to search Notion, or wants to inspect which Notion accounts they're signed into.
---

# Notion CLI

Read Notion via the unofficial `/api/v3` endpoint using `token_v2` from the user's browser (Arc by default). Sees every page their logged-in browser sees — including pages shared by guests from other workspaces, which the official API can't reach without per-page integration grants.

## Prerequisites

- User signed into Notion web in a Chromium-family browser (Arc, Chrome, Chromium, Brave, Edge, Firefox, Safari)
- `uv` installed — the script is PEP 723 so `uv run` self-resolves dependencies (`browser-cookie3`, `chromium-reader`, `diskcache`, `pydantic`, `requests`, `rich`, `typer`)

## Commands

All commands use `notion.py` from this skill dir. Default browser is Arc; override with `-b chrome|brave|edge|firefox|safari|chromium`.

### Fetch a page as Markdown

```bash
./notion.py get <page-id-or-url>           # → stdout
./notion.py get <page-id-or-url> -o out.md # → file
./notion.py get <page-id-or-url> --raw     # raw recordMap JSON instead of rendered Markdown
```

`<page-id-or-url>` accepts:
- Full Notion URL: `https://www.notion.so/Page-Title-292ff732fc3480d0a39ee6a78db70f82`
- 32-hex slug tail: `292ff732fc3480d0a39ee6a78db70f82`
- Dashed UUID: `292ff732-fc34-80d0-a39e-e6a78db70f82`

Renders headings, paragraphs, bullets, numbered lists, code (language preserved), quotes, callouts, dividers, bookmarks, images, to-dos, toggles. Empty `language=markdown` code blocks (a Notion authoring quirk) are unwrapped.

### List logged-in identities

```bash
./notion.py whoami
```

Enumerates each browser profile with a `token_v2` cookie and prints the user + workspaces. Useful for figuring out which Arc profile has a particular workspace.

### Search a workspace

```bash
./notion.py search "<query>" --space <space-id>
./notion.py search "<query>" --from-page <page-id>   # resolve space from a page you can access
```

Slack-style workspace search. `--from-page` is the easier path when you don't know the space ID off-hand.

## Auth

Browser cookies do everything — no env vars, no tokens to manage. If a profile has Notion cookies, that profile's identity is used. With multiple profiles signed into different Notion accounts, the script uses cookies from the profile that can resolve the page.

## When to use this skill

- **Use** when the user mentions a Notion URL/page-ID, asks to import a page into the KB, wants to scan their Notion accounts, or asks to search a workspace.
- **Don't use** for actions that mutate Notion (the official API + integration grants are still required for writes; this CLI is read-only).

## Examples

```bash
# Import a guest-shared RunPod page into the KB
./notion.py get https://www.notion.so/Creating-an-Account-and-SSH-into-Cluster-292ff732fc3480d0a39ee6a78db70f82 \
  -o projects/anthropic-fellows/program-handbook/runpod-ssh.md

# List which Notion accounts you're signed into across Arc profiles
./notion.py whoami

# Find pages in RunPod's workspace mentioning "cluster troubleshooting"
./notion.py search "cluster troubleshooting" --from-page 292ff732fc3480d0a39ee6a78db70f82
```

## Caching

Responses are memoized to `/tmp/tmp-kbnotion-{YYYY-MM-DD}` — a fresh dir per day, so cache rolls automatically. Pydantic models (`NotionBlock`, etc.) round-trip cleanly because `_caching` uses `model_dump`/`model_validate` for BaseModel returns.

## Local files

- `notion.py` — the CLI (PEP 723 inline deps, runs via `uv run`)
- `_caching.py` — disk-cache decorator that knows how to encode pydantic models; vendored copy of `kb/bin/shared/cached.py`
