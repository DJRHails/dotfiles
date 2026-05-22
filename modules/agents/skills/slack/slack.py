#!/usr/bin/env -S uv run
# /// script
# dependencies = ["browser-cookie3", "chromium-reader", "diskcache", "pydantic", "requests", "rich", "typer"]
# ///

"""Download Slack files from the CLI using browser cookies + a workspace token.

One-time setup: grab your xoxc token (any logged-in Slack web tab → DevTools
Console → `copy(TS.boot_data.api_token)`) and export it as $SLACK_TOKEN.

    bin/slack.py download F0A8SHNBR2N -o out.md
    bin/slack.py info F0A8SHNBR2N
"""

import glob
import http.cookiejar
import os
import re
import sys
from datetime import date
from enum import Enum
from pathlib import Path

import browser_cookie3
import diskcache
import requests
import typer
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from rich.console import Console
from _caching import cached

# Daily-rolling cache for Slack API responses — keyed on (function, args).
# `users.list` paginates over hundreds of members; `files.info` rarely changes.
# Token rotation naturally invalidates the key because the encoder includes it.
_cache = diskcache.Cache(f"/tmp/slack-cli-{date.today()}")


class _ApiModel(BaseModel):
    """Base for Slack API response models; ignores unknown fields."""

    model_config = ConfigDict(extra="ignore")


class SlackAuthTest(_ApiModel):
    """Subset of `auth.test` we read during token discovery."""

    ok: bool = False
    url: str | None = None
    team: str | None = None
    user: str | None = None


class SlackFile(_ApiModel):
    """Subset of a Slack file object used by `files info|download|search`."""

    id: str | None = None
    name: str | None = None
    mimetype: str | None = None
    size: int = 0
    user: str | None = None
    user_team: str | None = None
    username: str | None = None
    title: str | None = None
    url_private: str | None = None
    url_private_download: str | None = None
    permalink: str | None = None


class SlackFilesInfo(_ApiModel):
    """Top-level `files.info` payload."""

    ok: bool = False
    file: SlackFile = Field(default_factory=SlackFile)


class SlackFileMatches(_ApiModel):
    """`search.files.files` container."""

    total: int = 0
    matches: list[SlackFile] = Field(default_factory=list)


class SlackFileSearchResult(_ApiModel):
    """Top-level `search.files` payload."""

    ok: bool = False
    files: SlackFileMatches = Field(default_factory=SlackFileMatches)


class SlackMessageChannel(_ApiModel):
    """Nested channel ref on a message match."""

    name: str | None = None


class SlackMessageMatch(_ApiModel):
    """Subset of a message-search match."""

    text: str | None = None
    permalink: str | None = None
    user: str | None = None
    username: str | None = None
    channel: SlackMessageChannel = Field(default_factory=SlackMessageChannel)


class SlackMessageMatches(_ApiModel):
    """`search.messages.messages` container."""

    total: int = 0
    matches: list[SlackMessageMatch] = Field(default_factory=list)


class SlackMessageSearchResult(_ApiModel):
    """Top-level `search.messages` payload."""

    ok: bool = False
    messages: SlackMessageMatches = Field(default_factory=SlackMessageMatches)


class SlackUserProfile(_ApiModel):
    """Subset of a user's profile object."""

    real_name: str | None = None
    display_name: str | None = None
    email: str | None = None
    title: str | None = None


class SlackUser(_ApiModel):
    """Subset of a Slack user (member) record."""

    id: str | None = None
    name: str | None = None
    real_name: str | None = None
    deleted: bool = False
    profile: SlackUserProfile = Field(default_factory=SlackUserProfile)


class SlackResponseMetadata(_ApiModel):
    next_cursor: str | None = None


class SlackUsersList(_ApiModel):
    """Top-level `users.list` payload."""

    ok: bool = False
    members: list[SlackUser] = Field(default_factory=list)
    response_metadata: SlackResponseMetadata = Field(default_factory=SlackResponseMetadata)

app = typer.Typer(add_completion=False, no_args_is_help=True)
files_app = typer.Typer(add_completion=False, no_args_is_help=True, help="Inspect, search, and download files.")
messages_app = typer.Typer(add_completion=False, no_args_is_help=True, help="Search messages.")
users_app = typer.Typer(add_completion=False, no_args_is_help=True, help="Look up users (resolve display name → @handle for `from:` filters).")
app.add_typer(files_app, name="files")
app.add_typer(messages_app, name="messages")
app.add_typer(users_app, name="users")
err = Console(stderr=True)

_VERBOSE = bool(os.environ.get("SLACK_VERBOSE"))


@app.callback()
def _root(verbose: bool = typer.Option(False, "--verbose", "-v", help="Print auto-discovery details to stderr.")) -> None:
    global _VERBOSE
    _VERBOSE = _VERBOSE or verbose


def _vprint(msg: str) -> None:
    if _VERBOSE:
        err.print(msg)


class Browser(str, Enum):
    arc = "arc"
    chrome = "chrome"
    chromium = "chromium"
    brave = "brave"
    edge = "edge"
    firefox = "firefox"
    safari = "safari"


_CHROMIUM_PROFILE_GLOBS = {
    Browser.arc: "~/Library/Application Support/Arc/User Data/{Default,Profile *}/Cookies",
    Browser.chrome: "~/Library/Application Support/Google/Chrome/{Default,Profile *}/Cookies",
    Browser.chromium: "~/Library/Application Support/Chromium/{Default,Profile *}/Cookies",
    Browser.brave: "~/Library/Application Support/BraveSoftware/Brave-Browser/{Default,Profile *}/Cookies",
    Browser.edge: "~/Library/Application Support/Microsoft Edge/{Default,Profile *}/Cookies",
}

_BROWSER_LEVELDB_GLOBS = {
    Browser.arc: "~/Library/Application Support/Arc/User Data/{Default,Profile *}/Local Storage/leveldb",
    Browser.chrome: "~/Library/Application Support/Google/Chrome/{Default,Profile *}/Local Storage/leveldb",
    Browser.chromium: "~/Library/Application Support/Chromium/{Default,Profile *}/Local Storage/leveldb",
    Browser.brave: "~/Library/Application Support/BraveSoftware/Brave-Browser/{Default,Profile *}/Local Storage/leveldb",
    Browser.edge: "~/Library/Application Support/Microsoft Edge/{Default,Profile *}/Local Storage/leveldb",
}

_XOXC_RE = re.compile(
    r"""(?x)            # verbose
    xoxc-               # literal token prefix
    [A-Za-z0-9-]+       # body: alnum and hyphen
    """
)


def _expand_brace_glob(pattern: str) -> list[str]:
    parts = re.match(r"^(.*)\{(.+)\}(.*)$", pattern)
    if not parts:
        return sorted(glob.glob(os.path.expanduser(pattern)))
    prefix, alts, suffix = parts.group(1), parts.group(2).split(","), parts.group(3)
    return sorted(p for alt in alts for p in glob.glob(os.path.expanduser(f"{prefix}{alt}{suffix}")))


def _profile_cookie_files(browser: Browser) -> list[str]:
    pattern = _CHROMIUM_PROFILE_GLOBS.get(browser)
    return _expand_brace_glob(pattern) if pattern else []


def _profile_leveldb_dirs(browser: Browser) -> list[str]:
    pattern = _BROWSER_LEVELDB_GLOBS.get(browser)
    return _expand_brace_glob(pattern) if pattern else []


def _cookies(browser: Browser) -> http.cookiejar.CookieJar:
    loader = getattr(browser_cookie3, browser.value)
    merged = http.cookiejar.CookieJar()
    for cf in _profile_cookie_files(browser) or [None]:
        try:
            jar = loader(cookie_file=cf, domain_name=".slack.com") if cf else loader(domain_name=".slack.com")
        except Exception as e:
            err.print(f"[yellow]skipping {cf or browser.value}: {type(e).__name__}: {e}[/yellow]")
            continue
        for c in jar:
            merged.set_cookie(c)
    if not any(c.name == "d" for c in merged):
        err.print(f"[red]no Slack `d` cookie found in {browser.value}[/red] — are you signed into Slack web?")
        raise typer.Exit(2)
    return merged


_TOKEN_PATH = Path.home() / ".config" / "slack" / "token"


def _tokens_from_browser(browser: Browser) -> list[str]:
    """Discover xoxc tokens from a Chromium browser's localStorage leveldb stores.

    Uses chromium-reader, which decodes the leveldb framing properly and returns
    full untruncated string values. Returns de-duplicated tokens, longest first.
    """
    found: set[str] = set()
    for ldb in _profile_leveldb_dirs(browser):
        found.update(_tokens_from_leveldb(ldb))
    return sorted(found, key=len, reverse=True)


@cached(_cache)
def _tokens_from_leveldb(ldb_dir: str) -> set[str]:
    """Extract all xoxc tokens from a single Local Storage/leveldb directory."""
    from chromium_reader.localstorage import LocalStorageReader

    found: set[str] = set()
    try:
        reader = LocalStorageReader(ldb_dir)
    except Exception as e:
        err.print(f"[yellow]skipping {ldb_dir}: {type(e).__name__}: {e}[/yellow]")
        return found
    try:
        for rec in reader.records():
            v = rec.value
            if not isinstance(v, str) or "xoxc-" not in v:
                continue
            for match in _XOXC_RE.finditer(v):
                found.add(match.group(0))
    finally:
        reader.close()
    return found


def _tokens_by_profile(browser: Browser) -> list[tuple[str, set[str], str | None]]:
    """Pair each browser profile with its (leveldb tokens, cookie file path).

    Returns (profile_label, tokens, cookie_path) tuples for profiles with at least
    one xoxc token. Cookies need to be paired with their own profile because Slack's
    `d` cookie is keyed only on `.slack.com` — merging profiles overwrites it.
    """
    out: list[tuple[str, set[str], str | None]] = []
    for ldb in _profile_leveldb_dirs(browser):
        # ldb = .../<Profile>/Local Storage/leveldb → profile_root = .../<Profile>
        profile_root = os.path.dirname(os.path.dirname(ldb))
        tokens = _tokens_from_leveldb(ldb)
        if not tokens:
            continue
        ck = os.path.join(profile_root, "Cookies")
        out.append((os.path.basename(profile_root), tokens, ck if os.path.isfile(ck) else None))
    return out


def _profile_cookie_jar(browser: Browser, cookie_file: str | None) -> http.cookiejar.CookieJar:
    """Load .slack.com cookies from a single profile's cookie file."""
    loader = getattr(browser_cookie3, browser.value)
    jar = http.cookiejar.CookieJar()
    if not cookie_file:
        return jar
    try:
        for c in loader(cookie_file=cookie_file, domain_name=".slack.com"):
            jar.set_cookie(c)
    except Exception as e:
        err.print(f"[yellow]skipping cookies {cookie_file}: {type(e).__name__}: {e}[/yellow]")
    return jar


_DISCOVERED_WORKSPACE: str | None = None  # set by _token when a token's team url is known


@cached(_cache)
def _auth_test(token: str, host: str, jar: http.cookiejar.CookieJar) -> SlackAuthTest | None:
    """Run `auth.test` against `<host>.slack.com`; return parsed response on ok, else None.

    `@cached` handles the model encode/decode and the None sentinel — failed probes
    cache too (otherwise the discovery loop pays full network cost on every invocation)."""
    try:
        r = requests.get(
            f"https://{host}.slack.com/api/auth.test",
            params={"token": token},
            cookies=jar,
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=10,
        )
    except requests.RequestException:
        return None
    if r.status_code != 200:
        return None
    try:
        data = SlackAuthTest.model_validate(r.json())
    except ValidationError:
        return None
    return data if data.ok else None


def _workspace_from_url(url: str) -> str | None:
    """Extract the workspace subdomain from a team url like https://foo.slack.com/."""
    m = re.match(r"https?://([^.]+)\.slack\.com", url or "")
    return m.group(1) if m else None


def _discover_token(browser: Browser, jar: http.cookiejar.CookieJar) -> str | None:
    """Probe browser profiles for a usable xoxc token; return the best (token, workspace).

    Sets `_DISCOVERED_WORKSPACE` and (when possible) replaces `jar`'s cookies in-place
    with the cookies from the profile whose token won. Returns the token, or None.
    """
    global _DISCOVERED_WORKSPACE
    profiles = _tokens_by_profile(browser)
    n_tokens = sum(len(toks) for _, toks, _ in profiles)
    if not profiles:
        return None
    _vprint(f"[dim]auto-discovery: {n_tokens} candidate(s) across {len(profiles)} profile(s)[/dim]")
    explicit_ws = os.environ.get("SLACK_WORKSPACE")
    preferred = {"astra-fellowship", "anthropic"}
    validated: list[tuple[str, str | None, str, http.cookiejar.CookieJar]] = []
    for profile, tokens, ck in profiles:
        profile_jar = _profile_cookie_jar(browser, ck)
        for tok in sorted(tokens, key=len, reverse=True):
            data = _auth_test(tok, "slack", profile_jar)
            if data is None:
                continue
            ws = _workspace_from_url(data.url or "")
            team = data.team or "?"
            if explicit_ws and ws != explicit_ws:
                continue
            validated.append((tok, ws, team, profile_jar))
            _vprint(f"[dim]  [{profile}] team={team} workspace={ws}[/dim]")
    if not validated:
        return None
    validated.sort(key=lambda t: (t[1] not in preferred, t[1] or ""))
    tok, ws, team, profile_jar = validated[0]
    if ws:
        _DISCOVERED_WORKSPACE = ws
    jar._cookies.clear()  # type: ignore[attr-defined]
    for c in profile_jar:
        jar.set_cookie(c)
    _vprint(f"[green]✔ token len={len(tok)} team={team} ws={ws or '?'}[/green]")
    return tok


def _token(browser: Browser = Browser.arc, jar: http.cookiejar.CookieJar | None = None) -> str:
    """Resolve an xoxc token from env, config file, or browser localStorage auto-discovery."""
    tok = os.environ.get("SLACK_TOKEN") or os.environ.get("SLACK_XOXC_TOKEN")
    if not tok and _TOKEN_PATH.exists():
        tok = _TOKEN_PATH.read_text().strip()
    if tok and tok.startswith(("xoxc-", "xoxs-", "xoxe-")):
        return tok
    if jar is None:
        jar = _cookies(browser)
    discovered = _discover_token(browser, jar)
    if discovered:
        return discovered
    err.print(
        f"[red]no SLACK_TOKEN set and no valid xoxc token in {browser.value} localStorage.[/red]\n"
        "Either sign into Slack web (in Arc), or run [bold]bin/slack.py bootstrap[/bold]."
    )
    raise typer.Exit(2)


def _workspace_hosts() -> list[str]:
    # Probed in order until one accepts the token. Override via $SLACK_WORKSPACE.
    # Auto-discovery (_token) populates _DISCOVERED_WORKSPACE from auth.test's team url.
    if ws := os.environ.get("SLACK_WORKSPACE"):
        return [ws]
    if _DISCOVERED_WORKSPACE:
        return [_DISCOVERED_WORKSPACE]
    return ["astra-fellowship", "anthropic", "slack"]


def _api(method: str, jar, token: str, **params) -> dict:
    """Call a Slack web-API method; probes workspace hosts until one accepts."""
    last_err = None
    for ws in _workspace_hosts():
        r = requests.get(
            f"https://{ws}.slack.com/api/{method}",
            params={**params, "token": token},
            cookies=jar,
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=30,
        )
        if r.status_code != 200:
            last_err = f"{ws}: HTTP {r.status_code}"
            continue
        data = r.json()
        if data.get("ok"):
            return data
        last_err = f"{ws}: {data.get('error', 'unknown')}"
    err.print(f"[red]{method} failed across workspaces:[/red] {last_err}")
    raise typer.Exit(2)


@cached(_cache)
def _files_info(file_id: str, jar, token: str) -> SlackFile:
    """Call `files.info` and return the parsed file record. Cached daily."""
    raw = _api("files.info", jar, token, file=file_id)
    try:
        return SlackFilesInfo.model_validate(raw).file
    except ValidationError as e:
        err.print(f"[red]files.info payload failed validation:[/red] {e}")
        raise typer.Exit(2) from e


@files_app.command("info")
def files_info(
    file_id: str = typer.Argument(..., help="Slack file ID (e.g. F0A8SHNBR2N)"),
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b"),
) -> None:
    """Print file metadata (name, size, uploader, download URL)."""
    jar = _cookies(browser)
    f = _files_info(file_id, jar, _token(browser, jar))
    console = Console()
    console.print(f"[bold]{f.name or '?'}[/bold]  [dim]({f.mimetype or '?'}, {f.size:,}B)[/dim]")
    console.print(f"  uploader: {f.user or '?'}  team: {f.user_team or '?'}")
    if f.title and f.title != f.name:
        console.print(f"  title: {f.title}")
    if f.url_private_download:
        console.print(f"  [dim]{f.url_private_download}[/dim]")


@files_app.command("download")
def files_download(
    file_id: str = typer.Argument(..., help="Slack file ID (e.g. F0A8SHNBR2N)"),
    out: Path | None = typer.Option(None, "--out", "-o", help="Output path; default: file's own name in cwd"),
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b"),
) -> None:
    """Download a file from Slack by ID."""
    jar = _cookies(browser)
    tok = _token(browser, jar)
    f = _files_info(file_id, jar, tok)
    url = f.url_private_download or f.url_private
    if not url:
        err.print("[red]file has no download URL (may be a snippet)[/red]")
        raise typer.Exit(2)
    r = requests.get(
        url, cookies=jar,
        headers={"Authorization": f"Bearer {tok}", "User-Agent": "Mozilla/5.0"},
        allow_redirects=True, timeout=60,
    )
    if r.status_code != 200 or "text/html" in r.headers.get("content-type", ""):
        err.print(f"[red]download failed:[/red] HTTP {r.status_code}, ct={r.headers.get('content-type', '?')}")
        raise typer.Exit(2)
    dest = out or Path(f.name or file_id)
    dest.write_bytes(r.content)
    err.print(f"[green]wrote {len(r.content):,} bytes to {dest}[/green]")


@files_app.command("search")
def files_search(
    query: str = typer.Argument(..., help="Slack syntax: 'filename:*.md', 'from:@<handle>', 'in:#chan'. Use `users search` to resolve display name → handle."),
    count: int = typer.Option(20, "--count", "-n", help="Max results"),
    page: int = typer.Option(1, "--page", "-p", help="1-indexed page"),
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b"),
) -> None:
    """Search Slack files. Use IDs from output with `files download`."""
    jar = _cookies(browser)
    raw = _api("search.files", jar, _token(browser, jar),
               query=query, count=count, page=page, sort="timestamp", sort_dir="desc")
    try:
        resp = SlackFileSearchResult.model_validate(raw)
    except ValidationError as e:
        err.print(f"[red]search.files payload failed validation:[/red] {e}")
        raise typer.Exit(2) from e
    matches = resp.files.matches
    console = Console()
    console.print(f"[dim]{len(matches)} of {resp.files.total or len(matches)} matches[/dim]")
    for f in matches:
        console.print(f"[bold]{f.id}[/bold]  {f.name or '?'}  "
                      f"[dim]({f.mimetype or '?'}, {f.size:,}B)[/dim]")
        uploader = f.username or f.user or "?"
        console.print(f"  by [cyan]{uploader}[/cyan]  [dim]{f.permalink or ''}[/dim]")


@messages_app.command("search")
def messages_search(
    query: str = typer.Argument(..., help="Slack syntax: 'from:@<handle>' (use `users search` to resolve), 'in:#chan', 'has:link'"),
    count: int = typer.Option(20, "--count", "-n", help="Max results"),
    page: int = typer.Option(1, "--page", "-p", help="1-indexed page"),
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b"),
) -> None:
    """Search Slack messages."""
    jar = _cookies(browser)
    raw = _api("search.messages", jar, _token(browser, jar),
               query=query, count=count, page=page, sort="timestamp", sort_dir="desc")
    try:
        resp = SlackMessageSearchResult.model_validate(raw)
    except ValidationError as e:
        err.print(f"[red]search.messages payload failed validation:[/red] {e}")
        raise typer.Exit(2) from e
    matches = resp.messages.matches
    console = Console()
    console.print(f"[dim]{len(matches)} of {resp.messages.total or len(matches)} matches[/dim]")
    for m in matches:
        ch = m.channel.name or "?"
        user = m.username or m.user or "?"
        text = (m.text or "").replace("\n", " ")[:140]
        console.print(f"[bold]#{ch}[/bold]  [cyan]{user}[/cyan]: {text}")
        if m.permalink:
            console.print(f"  [dim]{m.permalink}[/dim]")


@cached(_cache)
def _users_list_all(jar, token, max_pages: int = 20) -> list[SlackUser]:
    """Paginate `users.list` and return every validated member record. Cached daily;
    `@cached` handles encode/decode of the list[SlackUser]."""
    members: list[SlackUser] = []
    cursor: str | None = None
    for _ in range(max_pages):
        params: dict = {"limit": 200}
        if cursor:
            params["cursor"] = cursor
        raw = _api("users.list", jar, token, **params)
        try:
            page = SlackUsersList.model_validate(raw)
        except ValidationError as e:
            err.print(f"[red]users.list payload failed validation:[/red] {e}")
            raise typer.Exit(2) from e
        members.extend(page.members)
        cursor = page.response_metadata.next_cursor or None
        if not cursor:
            break
    return members


def _user_matches(member: SlackUser, q: str) -> bool:
    q = q.lower()
    haystacks = [
        member.name or "",
        member.real_name or "",
        member.profile.real_name or "",
        member.profile.display_name or "",
        member.profile.email or "",
    ]
    return any(q in h.lower() for h in haystacks)


@users_app.command("search")
def users_search(
    query: str = typer.Argument(..., help="Substring to match against handle / real name / display name / email"),
    count: int = typer.Option(10, "--count", "-n", help="Max results to print"),
    browser: Browser = typer.Option(Browser.arc, "--browser", "-b"),
) -> None:
    """Resolve a display name or partial handle to a Slack @handle.

    Returns the `name` field of each matching user — that's what `from:@<handle>`
    in `files search` / `messages search` expects. Paginates `users.list` and
    filters locally; one round-trip per ~200 users in the workspace.
    """
    jar = _cookies(browser)
    members = _users_list_all(jar, _token(browser, jar))
    matches = [m for m in members if not m.deleted and _user_matches(m, query)]
    console = Console()
    if not matches:
        console.print(f"[yellow]no users matched {query!r}[/yellow] (searched {len(members)} members)")
        return
    console.print(f"[dim]{len(matches)} match{'es' if len(matches) != 1 else ''} of {len(members)} members[/dim]")
    for u in matches[:count]:
        handle = u.name or "?"
        real = u.real_name or u.profile.real_name or ""
        display = u.profile.display_name or ""
        title = u.profile.title or ""
        bits = [f"[bold]@{handle}[/bold]"]
        if real and real != handle:
            bits.append(real)
        if display and display not in (handle, real):
            bits.append(f"({display})")
        if title:
            bits.append(f"[dim]{title}[/dim]")
        console.print("  " + "  ".join(bits) + f"  [dim]{u.id or '?'}[/dim]")


@app.command()
def bootstrap() -> None:
    """One-time: capture an xoxc token from clipboard or stdin, save to ~/.config/slack/token."""
    import subprocess
    console = Console()
    tok = ""
    try:
        tok = subprocess.run(["pbpaste"], capture_output=True, text=True, timeout=2).stdout.strip()
    except (FileNotFoundError, subprocess.SubprocessError):
        pass
    if not tok.startswith("xoxc-"):
        console.print("Open https://app.slack.com/, DevTools Console, run: [bold]copy(TS.boot_data.api_token)[/bold]")
        console.print("Then paste here (or pipe in) and press Ctrl-D:")
        tok = sys.stdin.read().strip()
    if not tok.startswith(("xoxc-", "xoxs-", "xoxe-")):
        err.print(f"[red]not an xoxc/xoxs/xoxe token: {tok[:20]!r}…[/red]")
        raise typer.Exit(2)
    _TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    _TOKEN_PATH.write_text(tok)
    _TOKEN_PATH.chmod(0o600)
    jar = _cookies(Browser.arc)
    method, url = "auth.test", None
    for ws in _workspace_hosts():
        r = requests.get(f"https://{ws}.slack.com/api/{method}", params={"token": tok},
                         cookies=jar, headers={"User-Agent": "Mozilla/5.0"}, timeout=10)
        try:
            d = SlackAuthTest.model_validate(r.json()) if r.status_code == 200 else SlackAuthTest()
        except (ValueError, ValidationError):
            continue
        if d.ok:
            console.print(f"[green]✔ saved → {_TOKEN_PATH}[/green]")
            console.print(f"  team: {d.team}  user: {d.user}  url: {d.url}")
            return
    err.print(f"[yellow]saved but auth.test rejected the token across {_workspace_hosts()}[/yellow]")


if __name__ == "__main__":
    app()
