#!/usr/bin/env -S uv run
# /// script
# dependencies = ["browser-cookie3", "diskcache", "emboss", "pydantic", "requests", "rich", "typer"]
# ///

"""Fetch Notion pages via the unofficial /api/v3 endpoint using browser cookies.

Reads `token_v2` from your browser's cookie store (Arc by default), so it sees
every page your logged-in browser sees — no integration grants, no guest fuss.
"""

import glob
import http.cookiejar
import json
import os
import re
import sys
from datetime import date
from enum import Enum
from pathlib import Path
from typing import Any

import browser_cookie3
import diskcache
import requests
import typer
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from rich.console import Console
from emboss import cached

# Daily-rolling cache for Notion page fetches. Each `_collect_blocks` call
# can be many round-trips through `loadPageChunk`; caching by page_uuid
# makes repeat reads instant. Token rotation invalidates the key.
_cache = diskcache.Cache(f"/tmp/notion-cli-{date.today()}")

app = typer.Typer(add_completion=False, no_args_is_help=True)
err = Console(stderr=True)


class _ApiModel(BaseModel):
    """Base for Notion API response models; ignores unknown fields."""

    model_config = ConfigDict(extra="ignore")


class NotionBlock(_ApiModel):
    """Subset of a Notion block record (post-unwrap).

    `properties` is a free-form dict of rich-text run arrays keyed by property
    name (`title`, `language`, `source`, `link`, `checked`, ...). Same for
    `format`. They stay `dict[str, Any]` — modelling rich-text runs adds noise
    without paying off.
    """

    id: str | None = None
    type: str | None = None
    space_id: str | None = None
    properties: dict[str, Any] = Field(default_factory=dict)
    content: list[str] = Field(default_factory=list)


class NotionSpace(_ApiModel):
    """A workspace as surfaced in `getSpaces`."""

    id: str
    name: str


class NotionIdentity(_ApiModel):
    """One logged-in identity (user + their workspaces) for `whoami`."""

    user: str = "?"
    email: str = "?"
    spaces: list[NotionSpace] = Field(default_factory=list)


class NotionSearchHit(_ApiModel):
    """One hit from the `search` endpoint's `results` array."""

    id: str | None = None


class NotionSearchResponse(_ApiModel):
    """Top-level `search` payload — `recordMap.block.<id>` is double-wrapped."""

    results: list[NotionSearchHit] = Field(default_factory=list)
    recordMap: dict[str, Any] = Field(default_factory=dict)

NOTION_API = "https://www.notion.so/api/v3"
PAGE_ID_RE = re.compile(
    r"""(?ix)
    (?P<id>[0-9a-f]{32}        # raw 32-hex form (URL slug tail)
        | [0-9a-f]{8} - [0-9a-f]{4} - [0-9a-f]{4} - [0-9a-f]{4} - [0-9a-f]{12}
    )
    """
)


class Browser(str, Enum):
    arc = "arc"
    chrome = "chrome"
    chromium = "chromium"
    brave = "brave"
    edge = "edge"
    firefox = "firefox"
    safari = "safari"


def _to_uuid(page_id: str) -> str:
    m = PAGE_ID_RE.search(page_id)
    if not m:
        raise typer.BadParameter(f"could not find a Notion page id in {page_id!r}")
    raw = m.group("id").replace("-", "")
    return f"{raw[0:8]}-{raw[8:12]}-{raw[12:16]}-{raw[16:20]}-{raw[20:32]}"


# Chromium-based browsers: bc3 only reads the first profile via its glob. Enumerate
# them ourselves so multi-profile setups (Arc spaces, Chrome profiles) work.
_CHROMIUM_PROFILE_GLOBS = {
    Browser.arc: "~/Library/Application Support/Arc/User Data/{Default,Profile *}/Cookies",
    Browser.chrome: "~/Library/Application Support/Google/Chrome/{Default,Profile *}/Cookies",
    Browser.chromium: "~/Library/Application Support/Chromium/{Default,Profile *}/Cookies",
    Browser.brave: "~/Library/Application Support/BraveSoftware/Brave-Browser/{Default,Profile *}/Cookies",
    Browser.edge: "~/Library/Application Support/Microsoft Edge/{Default,Profile *}/Cookies",
}


def _profile_cookie_files(browser: Browser) -> list[str]:
    pattern = _CHROMIUM_PROFILE_GLOBS.get(browser)
    if not pattern:
        return []
    # glob doesn't understand brace expansion; split manually.
    parts = re.match(r"^(.*)\{(.+)\}(.*)$", pattern)
    if not parts:
        return sorted(glob.glob(os.path.expanduser(pattern)))
    prefix, alts, suffix = parts.group(1), parts.group(2).split(","), parts.group(3)
    files: list[str] = []
    for alt in alts:
        files.extend(glob.glob(os.path.expanduser(f"{prefix}{alt}{suffix}")))
    return sorted(files)


def _cookies_per_profile(browser: Browser) -> list[tuple[str, http.cookiejar.CookieJar]]:
    """Return one jar per browser profile that has a token_v2 cookie for .notion.so.

    Each entry is (profile_label, jar). Different profiles often belong to
    different Notion accounts; the unofficial API only honors one token_v2
    per request, so the caller picks which jar to use.
    """
    loader = getattr(browser_cookie3, browser.value)
    cookie_files = _profile_cookie_files(browser) or [None]
    out: list[tuple[str, http.cookiejar.CookieJar]] = []
    for cf in cookie_files:
        try:
            jar = loader(cookie_file=cf, domain_name=".notion.so") if cf else loader(domain_name=".notion.so")
        except Exception as e:
            err.print(f"[yellow]skipping {cf or browser.value}: {type(e).__name__}: {e}[/yellow]")
            continue
        if any(c.name == "token_v2" for c in jar):
            label = os.path.basename(os.path.dirname(cf)) if cf else browser.value
            out.append((label, jar))
    return out


def _cookies(browser: Browser) -> http.cookiejar.CookieJar:
    """Merged jar across all profiles — convenient when any token will do."""
    merged = http.cookiejar.CookieJar()
    for _, jar in _cookies_per_profile(browser):
        for c in jar:
            merged.set_cookie(c)
    if not any(c.name == "token_v2" for c in merged):
        err.print(
            f"[red]no token_v2 cookie found for .notion.so in {browser.value}.[/red] "
            "are you logged into notion in that browser?"
        )
        raise typer.Exit(2)
    return merged


def _post(path: str, payload: dict, jar) -> dict:
    """POST to the unofficial Notion API. Not cached itself — caching lives on
    the typed wrappers (`_collect_blocks`, `_space_id_for_page`) which now
    round-trip pydantic models cleanly via the model-aware `@cached`."""
    r = requests.post(
        f"{NOTION_API}/{path}",
        json=payload,
        cookies=jar,
        headers={
            "Content-Type": "application/json",
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0 Safari/537.36"
            ),
        },
        timeout=30,
    )
    if r.status_code == 401:
        err.print("[red]401 unauthorized[/red] — token_v2 cookie is stale; re-login in your browser")
        raise typer.Exit(2)
    r.raise_for_status()
    return r.json()


def _load_page_chunk(page_uuid: str, jar, chunk: int = 0) -> dict:
    return _post(
        "loadPageChunk",
        {
            "pageId": page_uuid,
            "limit": 100,
            "chunkNumber": chunk,
            "cursor": {"stack": []},
            "verticalColumns": False,
        },
        jar,
    )


@cached(_cache)
def _collect_blocks(page_uuid: str, jar) -> dict[str, NotionBlock]:
    """Walk `loadPageChunk` pagination and return validated blocks keyed by id.

    Cached daily; `@cached` encodes each NotionBlock to a dict before pickling
    and re-validates on read, sidestepping the __main__-class pickling issue."""
    blocks: dict[str, NotionBlock] = {}
    cursor: dict = {"stack": []}
    while True:
        resp = _post(
            "loadPageChunk",
            {
                "pageId": page_uuid,
                "limit": 100,
                "chunkNumber": 0,
                "cursor": cursor,
                "verticalColumns": False,
            },
            jar,
        )
        rmap = resp.get("recordMap", {}).get("block", {})
        for bid, entry in rmap.items():
            # API wraps as {"value": {"value": <block>, "role": "..."}}; older
            # responses had a single layer. Unwrap until we hit a dict with "type".
            val = entry
            for _ in range(3):
                if isinstance(val, dict) and "value" in val and "type" not in val:
                    val = val["value"]
                else:
                    break
            if isinstance(val, dict) and "type" in val:
                try:
                    blocks[bid] = NotionBlock.model_validate(val)
                except ValidationError as e:
                    err.print(f"[yellow]skipping block {bid}: {e}[/yellow]")
        cursor = resp.get("cursor", {"stack": []})
        if not cursor.get("stack"):
            break
    return blocks


def _rich_text(rich: list | None) -> str:
    if not rich:
        return ""
    out: list[str] = []
    for run in rich:
        if not run:
            continue
        text = run[0] if isinstance(run, list) else str(run)
        marks = run[1] if isinstance(run, list) and len(run) > 1 else []
        for mark in marks or []:
            kind = mark[0] if isinstance(mark, list) else mark
            if kind == "b":
                text = f"**{text}**"
            elif kind == "i":
                text = f"*{text}*"
            elif kind == "c":
                text = f"`{text}`"
            elif kind == "s":
                text = f"~~{text}~~"
            elif kind == "a" and isinstance(mark, list) and len(mark) > 1:
                text = f"[{text}]({mark[1]})"
        out.append(text)
    return "".join(out)


def _render(blocks: dict[str, NotionBlock], root: str) -> str:
    """Walk the block tree and render to Markdown. Minimal block-type coverage."""
    lines: list[str] = []

    def title_of(block: NotionBlock) -> str:
        return _rich_text(block.properties.get("title"))

    def walk(bid: str, depth: int, ordered_idx: int | None = None) -> None:
        block = blocks.get(bid)
        if not block:
            return
        btype = block.type or ""
        text = title_of(block)
        indent = "  " * depth

        if btype == "page" and depth == 0:
            if text:
                lines.append(f"# {text}\n")
        elif btype == "header":
            lines.append(f"\n## {text}\n")
        elif btype == "sub_header":
            lines.append(f"\n### {text}\n")
        elif btype == "sub_sub_header":
            lines.append(f"\n#### {text}\n")
        elif btype == "text":
            lines.append(f"{indent}{text}\n" if text else "")
        elif btype == "bulleted_list":
            lines.append(f"{indent}- {text}")
        elif btype == "numbered_list":
            n = ordered_idx if ordered_idx is not None else 1
            lines.append(f"{indent}{n}. {text}")
        elif btype == "to_do":
            checked = block.properties.get("checked") == [["Yes"]]
            box = "[x]" if checked else "[ ]"
            lines.append(f"{indent}- {box} {text}")
        elif btype == "quote":
            lines.append(f"> {text}\n")
        elif btype == "callout":
            lines.append(f"> **Note:** {text}\n")
        elif btype == "code":
            if not text.strip():
                pass  # drop empty code blocks; they create broken nested fences
            else:
                lang = (block.properties.get("language", [[""]]) or [[""]])[0][0].lower()
                if lang in {"markdown", "plain text", "plaintext", ""}:
                    # Notion authors often use markdown-language code blocks as prose
                    # boxes; render them as plain content so links/formatting render.
                    lines.append(f"{text}\n")
                else:
                    # Use a fence longer than any backtick run inside the body, so code
                    # blocks that themselves contain ``` round-trip cleanly.
                    longest = max((len(m.group(0)) for m in re.finditer(r"`+", text)), default=0)
                    fence = "`" * max(3, longest + 1)
                    lines.append(f"{fence}{lang}\n{text}\n{fence}\n")
        elif btype == "divider":
            lines.append("\n---\n")
        elif btype == "bookmark":
            link = (block.properties.get("link", [[""]]) or [[""]])[0][0]
            lines.append(f"- [{text or link}]({link})\n")
        elif btype in {"image", "video", "file", "pdf"}:
            src = (block.properties.get("source", [[""]]) or [[""]])[0][0]
            if btype == "image":
                lines.append(f"![{text}]({src})\n")
            else:
                lines.append(f"[{btype}: {text or src}]({src})\n")
        elif btype == "toggle":
            lines.append(f"{indent}- <details><summary>{text}</summary>\n")
        elif btype == "column_list" or btype == "column":
            pass  # render children only
        else:
            if text:
                lines.append(f"{indent}{text}  <!-- {btype} -->\n")

        # Recurse into children. Track numbering for numbered_list runs.
        children = block.content or []
        n = 1
        for cid in children:
            child = blocks.get(cid)
            child_type = child.type if child else None
            if child_type == "numbered_list":
                walk(cid, depth + 1 if btype not in {"page"} else 0, n)
                n += 1
            else:
                walk(cid, depth + 1 if btype not in {"page"} else 0)

    walk(root, 0)
    out = "\n".join(line for line in lines if line is not None)
    # Collapse runs of 3+ blank lines down to a single blank line.
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.rstrip() + "\n"


@app.command()
def get(
    page: str = typer.Argument(..., help="Notion page URL or 32-hex / UUID id"),
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b", help="Which browser's cookies to use"),
    out: Path | None = typer.Option(None, "--out", "-o", help="Write to file instead of stdout"),
    raw: bool = typer.Option(False, "--raw", help="Dump raw recordMap JSON instead of rendering Markdown"),
) -> None:
    """Fetch a Notion page as Markdown (or raw JSON)."""
    page_uuid = _to_uuid(page)
    jar = _cookies(browser)
    blocks = _collect_blocks(page_uuid, jar)
    if not blocks:
        err.print("[red]no blocks returned[/red] — page may not exist or cookie lacks access")
        raise typer.Exit(1)

    if raw:
        text = json.dumps(
            {bid: b.model_dump() for bid, b in blocks.items()},
            indent=2, ensure_ascii=False,
        )
    else:
        text = _render(blocks, page_uuid)

    if out:
        out.write_text(text)
        err.print(f"[green]wrote {len(text):,} chars to {out}[/green]")
    else:
        sys.stdout.write(text)


def _unwrap(entry):
    """Notion v3 wraps records as {"value": {"value": <real>, "role": "..."}} or
    {"value": <real>}. Unwrap until we hit the leaf dict."""
    val = entry
    for _ in range(3):
        if isinstance(val, dict) and "value" in val and not {"id", "type", "email", "name"} & val.keys():
            val = val["value"]
        else:
            break
    return val if isinstance(val, dict) else {}


def _identity(jar) -> list[NotionIdentity]:
    """Return one `NotionIdentity` per user surfaced by `getSpaces`."""
    out: list[NotionIdentity] = []
    try:
        resp = _post("getSpaces", {}, jar)
    except Exception:
        return out
    for user_id, bundle in resp.items():
        u = _unwrap(bundle.get("notion_user", {}).get(user_id, {}))
        spaces: list[NotionSpace] = []
        for sid, sentry in bundle.get("space", {}).items():
            s = _unwrap(sentry)
            spaces.append(NotionSpace(id=sid, name=s.get("name") or sid))
        out.append(NotionIdentity(
            user=u.get("name") or "?",
            email=u.get("email") or "?",
            spaces=spaces,
        ))
    return out


@app.command()
def whoami(
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b", help="Which browser's cookies to use"),
) -> None:
    """List every logged-in Notion identity across browser profiles."""
    console = Console()
    profiles = _cookies_per_profile(browser)
    if not profiles:
        err.print(f"[red]no token_v2 cookie found in any {browser.value} profile[/red]")
        raise typer.Exit(2)
    for label, jar in profiles:
        for ident in _identity(jar):
            n_sp = len(ident.spaces)
            console.print(
                f"[bold]{ident.user}[/bold] <{ident.email}>  "
                f"[dim]({label}, {n_sp} workspace{'s' if n_sp != 1 else ''})[/dim]"
            )
            for sp in ident.spaces:
                console.print(f"  - {sp.name}  [dim]{sp.id[:8]}[/dim]")


@cached(_cache)
def _space_id_for_page(page_uuid: str, jar) -> str | None:
    """Look up a page's parent space_id via syncRecordValues. Cached daily; the
    `_MISSING` sentinel in `@cached` means `None` returns also cache correctly."""
    resp = _post(
        "syncRecordValues",
        {"requests": [{"pointer": {"table": "block", "id": page_uuid}, "version": -1}]},
        jar,
    )
    raw = _unwrap(resp.get("recordMap", {}).get("block", {}).get(page_uuid, {}))
    try:
        return NotionBlock.model_validate(raw).space_id
    except ValidationError:
        return None


@app.command()
def search(
    query: str = typer.Argument(..., help="Text to search for"),
    space: str | None = typer.Option(None, "--space", "-s", help="Space ID (UUID) to search; omit if --from-page given"),
    from_page: str | None = typer.Option(None, "--from-page", "-p", help="Derive space from a page URL/id you can access"),
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b"),
    limit: int = typer.Option(10, "--limit", "-n"),
) -> None:
    """Search a Notion workspace. Tries each browser profile's token until one works."""
    if not space and not from_page:
        err.print("[red]provide --space <id> or --from-page <url|id>[/red]")
        raise typer.Exit(2)
    profiles = _cookies_per_profile(browser)
    if not profiles:
        err.print(f"[red]no token_v2 in any {browser.value} profile[/red]")
        raise typer.Exit(2)

    console = Console()
    target_space = space
    if from_page:
        page_uuid = _to_uuid(from_page)
        for label, jar in profiles:
            try:
                sid = _space_id_for_page(page_uuid, jar)
            except Exception:
                continue
            if sid:
                target_space = sid
                err.print(f"[dim]resolved space {sid[:8]} via {label}[/dim]")
                break
        if not target_space:
            err.print(f"[red]no profile could resolve space for page {page_uuid}[/red]")
            raise typer.Exit(2)

    payload = {
        "type": "BlocksInSpace",
        "query": query,
        "spaceId": target_space,
        "filters": {
            "isDeletedOnly": False, "excludeTemplates": False,
            "isNavigableOnly": True, "requireEditPermissions": False,
            "ancestors": [], "createdBy": [], "editedBy": [],
            "lastEditedTime": {}, "createdTime": {},
        },
        "sort": "Relevance",
        "limit": limit,
    }
    seen: set[str] = set()
    any_hits = False
    for label, jar in profiles:
        try:
            raw = _post("search", payload, jar)
        except Exception as e:
            err.print(f"[yellow]{label}: {type(e).__name__}: {e}[/yellow]")
            continue
        try:
            r = NotionSearchResponse.model_validate(raw)
        except ValidationError as e:
            err.print(f"[yellow]{label}: search payload failed validation: {e}[/yellow]")
            continue
        if not r.results:
            continue
        records = r.recordMap.get("block", {})
        for hit in r.results:
            hid = hit.id
            if not hid or hid in seen:
                continue
            seen.add(hid)
            any_hits = True
            raw_block = _unwrap(records.get(hid, {}))
            try:
                block = NotionBlock.model_validate(raw_block)
            except ValidationError:
                block = NotionBlock()
            title = _rich_text(block.properties.get("title")) or "(untitled)"
            url = f"https://www.notion.so/{hid.replace('-', '')}"
            console.print(f"[bold]{title}[/bold]")
            console.print(f"  [dim]{url}[/dim]  [dim]via {label}[/dim]")
        break  # first profile with hits is enough
    if not any_hits:
        console.print(f"[yellow]no results for {query!r} in space {target_space[:8]}[/yellow]")


if __name__ == "__main__":
    app()
