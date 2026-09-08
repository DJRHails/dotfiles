#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["browser-cookie3", "pydantic", "requests", "rich", "typer", "websocket-client"]
# ///

# ruff: noqa: B008
# B008 flags typer's `= typer.Option(...)` declarations, which are function-default calls by
# design; the sibling slack CLI in this skills tree declares its options the same way, so the
# rule is disabled here rather than rewriting one file into Annotated form.

"""Read and write Overleaf projects from the CLI using an existing web session.

Overleaf publishes no API, and its git bridge is a premium feature. This drives the same
endpoints the web editor drives, authenticated by the `overleaf_session2` cookie of a
logged-in browser — so it works on a free account.

    overleaf.py projects list
    overleaf.py push <project> ./staged --prune
    overleaf.py compile <project> --pdf paper.pdf

On a machine with the browser, that needs no setup: the session is read from its cookie
store (`-b chrome|firefox|arc|…`). Elsewhere — a server, a container, an ssh session whose
keyring is unreachable — supply it through `$OVERLEAF_SESSION_COOKIE` or
`~/.config/overleaf/session`, which `export-env` prints for you, and which wins over the
browser when set. `overleaf.py session` says whether the one it found still works.
"""

import http.cookiejar
import json
import os
import re
import shlex
import sys
import time
from collections.abc import Iterator
from enum import Enum
from mimetypes import guess_type
from pathlib import Path
from typing import Literal, TypeVar

import browser_cookie3
import requests
import typer
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from rich.console import Console

# Deliberately no response cache, unlike the sibling slack CLI. There, caching pays for
# token probing and hundred-page user pagination; here every call is a single cheap
# request whose whole value is being current. A cached project list hides a project
# created a minute ago, and a cached file body would make `push` skip a real edit — both
# wrong rather than merely stale. The one thing held is the CSRF token: a session
# credential rather than content, and only for the life of the process.
_CSRF_TOKENS: dict[str, str] = {}  # allow-dict: a page-path → token memo

DEFAULT_HOST = "www.overleaf.com"
SESSION_COOKIE = "overleaf_session2"
# Overleaf sits behind Google's load balancer, which pins a session to one backend with
# this cookie. The socket.io handshake and the websocket upgrade that follows it must
# reach the same backend, so it travels with every request rather than just the HTTP ones.
STICKY_COOKIE = "GCLB"


class _ApiModel(BaseModel):
    """Base for Overleaf response models; ignores fields we do not read."""

    model_config = ConfigDict(extra="ignore")


class _AliasedModel(BaseModel):
    """Base for models over Overleaf's camelCase payloads, read by either spelling."""

    model_config = ConfigDict(extra="ignore", populate_by_name=True)


class OverleafUser(_AliasedModel):
    """A user record, as the dashboard blob and `/user/personal_info` return it."""

    id: str | None = None
    email: str | None = None
    first_name: str | None = Field(default=None, alias="firstName")
    last_name: str | None = Field(default=None, alias="lastName")

    @property
    def label(self) -> str:
        """The email if known, else the name, else `?` — for one-line identity output."""
        name = " ".join(part for part in (self.first_name, self.last_name) if part)
        return self.email or name or "?"


class OverleafProject(_AliasedModel):
    """A project as the dashboard's prefetched blob lists it."""

    id: str
    name: str = ""
    last_updated: str | None = Field(default=None, alias="lastUpdated")
    access_level: str | None = Field(default=None, alias="accessLevel")
    archived: bool = False
    trashed: bool = False
    owner: OverleafUser | None = None

    @property
    def url(self) -> str:
        return f"https://{overleaf_host()}/project/{self.id}"

    @property
    def label(self) -> str:
        return self.name or self.id


class ProjectsBlob(_ApiModel):
    """The `ol-prefetchedProjectsBlob` meta payload on the dashboard page."""

    projects: list[OverleafProject] = Field(default_factory=list)


class NewProject(_ApiModel):
    """`POST /project/new` response."""

    project_id: str


class UploadedEntity(_ApiModel):
    """`POST /project/<id>/upload` response."""

    success: bool = False
    entity_id: str | None = None
    entity_type: Literal["doc", "file"] | None = None
    error: str | None = None


class CompileOutputFile(_ApiModel):
    """One artefact of a compile — the PDF, the log, the aux files."""

    path: str = ""
    url: str | None = None
    build: str | None = None
    type: str | None = None


class CompileResult(_AliasedModel):
    """`POST /project/<id>/compile` response, minus the fields we do not read."""

    status: str = "unknown"
    # The CLSI backend that ran the build; artefact downloads must be pinned to it, as the
    # editor pins them, or on a multi-backend deployment they can land on a backend that
    # never saw the build.
    clsi_server_id: str | None = Field(default=None, alias="clsiServerId")
    output_files: list[CompileOutputFile] = Field(default_factory=list, alias="outputFiles")

    def artefact(self, suffix: str) -> CompileOutputFile | None:
        """The first output file whose path ends with `suffix` (`.pdf`, `.log`)."""
        return next((f for f in self.output_files if f.path.endswith(suffix)), None)


class RemoteEntity(BaseModel):
    """One doc, file, or folder in a project tree, with the id write commands need.

    Overleaf splits text (`doc`) from binary (`file`), and the two are read and deleted
    through different endpoints, so the kind travels with the path everywhere.
    """

    model_config = ConfigDict(frozen=True)

    path: str
    id: str
    kind: Literal["doc", "file", "folder"]


class ProjectTree(BaseModel):
    """A project's entities keyed by path, plus the root folder id uploads target."""

    root_folder_id: str
    entities: list[RemoteEntity] = Field(default_factory=list)

    def by_path(self) -> dict[str, RemoteEntity]:  # allow-dict: a path index, not a payload
        return {entity.path: entity for entity in self.entities}

    def files(self) -> list[RemoteEntity]:
        """Every doc and file, folders excluded, sorted by path."""
        return sorted((e for e in self.entities if e.kind != "folder"), key=lambda e: e.path)


class NewProjectReq(BaseModel):
    """`POST /project/new` body."""

    projectName: str  # noqa: N815 — Overleaf's own field name, sent verbatim


class CompileReq(BaseModel):
    """`POST /project/<id>/compile` body, with the editor's own defaults."""

    draft: bool = False
    check: Literal["silent", "validate", "error"] = "silent"
    incrementalCompilesEnabled: bool = True  # noqa: N815 — Overleaf's own field name


class PushPlan(BaseModel):
    """What a push would do: the paths to add, replace, leave alone, and prune."""

    added: list[str] = Field(default_factory=list)
    replaced: list[str] = Field(default_factory=list)
    unchanged: list[str] = Field(default_factory=list)
    pruned: list[RemoteEntity] = Field(default_factory=list)

    @property
    def writes(self) -> list[str]:
        """Every path to upload, adds and replacements together, in a stable order."""
        return sorted(self.added + self.replaced)

    def is_empty(self) -> bool:
        return not (self.added or self.replaced or self.pruned)


app = typer.Typer(add_completion=False, no_args_is_help=True)
projects_app = typer.Typer(
    add_completion=False, no_args_is_help=True, help="List and create projects."
)
files_app = typer.Typer(
    add_completion=False, no_args_is_help=True, help="List, read, write, and delete project files."
)
app.add_typer(projects_app, name="projects")
app.add_typer(files_app, name="files")
err = Console(stderr=True)


def _load_env_file() -> None:
    """Pre-load `~/.config/overleaf/env` (`export VAR=value` lines) into `os.environ`.

    Lets a headless host run the CLI directly, rather than wrapping every invocation in
    `set -a; . ~/.config/overleaf/env; set +a`. Existing variables win — the file only
    fills gaps — and a missing file is silent.
    """
    path = Path.home() / ".config" / "overleaf" / "env"
    if not path.is_file():
        return
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return
    for raw in text.splitlines():
        line = raw.strip().removeprefix("export ")
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        os.environ.setdefault(key.strip(), value)


_load_env_file()

_VERBOSE = bool(os.environ.get("OVERLEAF_VERBOSE"))

_PROJECT_URL_RE = re.compile(
    r"""(?x)                    # verbose
    /project/                   # the dashboard's project path segment
    (?P<id> [0-9a-f]{24} )      # the mongo object id Overleaf keys projects by
    """
)
_PROJECT_ID_RE = re.compile(
    r"""(?x)                    # verbose
    \A                          # a bare id is the whole argument
    (?P<id> [0-9a-f]{24} )      # 24 lowercase hex digits
    \Z
    """
)
_BRACE_ALTERNATION = re.compile(
    r"""(?x)                    # verbose
    ^(?P<prefix> .* )           # everything before the brace
    \{ (?P<alts> .+ ) \}        # the comma-separated alternatives
    (?P<suffix> .* )$           # everything after it
    """
)
_META_CONTENT_RE = re.compile(
    r"""(?xs)                                  # verbose, dot matches newline
    <meta \s+                                  # the tag Overleaf bootstraps the page with
    (?=[^>]*? name="ol-(?P<name>[\w-]+)")      # its ol-* name, in any attribute order
    [^>]*? content="(?P<content>[^"]*)"        # the payload, HTML-escaped
    """
)


def overleaf_host() -> str:
    """The host to talk to; `$OVERLEAF_HOST` points at a self-hosted instance."""
    return os.environ.get("OVERLEAF_HOST", DEFAULT_HOST)


class Browser(str, Enum):
    """A browser whose cookie store the session can be read from."""

    chrome = "chrome"
    arc = "arc"
    brave = "brave"
    edge = "edge"
    chromium = "chromium"
    firefox = "firefox"
    safari = "safari"
    opera = "opera"
    vivaldi = "vivaldi"
    librewolf = "librewolf"


# Per-profile cookie stores, macOS and Linux. Firefox and Safari are absent deliberately:
# browser_cookie3 finds their single store itself.
_CHROMIUM_PROFILE_GLOBS = {
    Browser.chrome: (
        "~/Library/Application Support/Google/Chrome/{Default,Profile *}/Cookies",
        "~/.config/google-chrome/{Default,Profile *}/Cookies",
    ),
    Browser.arc: ("~/Library/Application Support/Arc/User Data/{Default,Profile *}/Cookies",),
    Browser.brave: (
        "~/Library/Application Support/BraveSoftware/Brave-Browser/{Default,Profile *}/Cookies",
        "~/.config/BraveSoftware/Brave-Browser/{Default,Profile *}/Cookies",
    ),
    Browser.edge: (
        "~/Library/Application Support/Microsoft Edge/{Default,Profile *}/Cookies",
        "~/.config/microsoft-edge/{Default,Profile *}/Cookies",
    ),
    Browser.chromium: (
        "~/Library/Application Support/Chromium/{Default,Profile *}/Cookies",
        "~/.config/chromium/{Default,Profile *}/Cookies",
    ),
    Browser.vivaldi: (
        "~/Library/Application Support/Vivaldi/{Default,Profile *}/Cookies",
        "~/.config/vivaldi/{Default,Profile *}/Cookies",
    ),
}


# The browser discovery reads from, set once by the root callback. A global rather than an
# option repeated on all ten commands: it applies to every one of them identically.
_BROWSER = Browser.chrome


@app.callback()
def _root(
    verbose: bool = typer.Option(False, "--verbose", "-v", help="Print session details to stderr."),
    browser: Browser = typer.Option(
        Browser.chrome, "--browser", "-b", help="Browser whose Overleaf session to use."
    ),
) -> None:
    global _VERBOSE, _BROWSER
    _VERBOSE = _VERBOSE or verbose
    _BROWSER = browser


def _vprint(message: str) -> None:
    if _VERBOSE:
        err.print(message)


def _mk_cookie(name: str, value: str, domain: str) -> http.cookiejar.Cookie:
    """A minimal host cookie for the requests jar."""
    return http.cookiejar.Cookie(
        version=0,
        name=name,
        value=value,
        port=None,
        port_specified=False,
        domain=domain,
        domain_specified=True,
        domain_initial_dot=domain.startswith("."),
        path="/",
        path_specified=True,
        secure=True,
        expires=None,
        discard=False,
        comment=None,
        comment_url=None,
        rest={},
        rfc2109=False,
    )


def _cookie_domain() -> str:
    """The cookie domain for the configured host (`www.overleaf.com` → `.overleaf.com`)."""
    return f".{overleaf_host().removeprefix('www.')}"


def _slurp(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


_CONFIG_DIR = Path.home() / ".config" / "overleaf"


def _configured_cookies() -> http.cookiejar.CookieJar | None:
    """A jar from the environment or `~/.config/overleaf/`, or None when nothing is set.

    Checked before the browser, because an explicitly supplied session is always what the
    caller meant, and it is the only path where no browser exists. The load-balancer
    cookie is optional but carried when present: without it a socket.io upgrade can land
    on a backend that does not know the session.
    """
    session = os.environ.get("OVERLEAF_SESSION_COOKIE") or _slurp(_CONFIG_DIR / "session")
    if not session:
        return None
    jar = http.cookiejar.CookieJar()
    domain = _cookie_domain()
    jar.set_cookie(_mk_cookie(SESSION_COOKIE, session, domain))
    if sticky := (os.environ.get("OVERLEAF_GCLB_COOKIE") or _slurp(_CONFIG_DIR / "gclb")):
        jar.set_cookie(_mk_cookie(STICKY_COOKIE, sticky, domain))
        _vprint("[dim]session: configured cookie + load-balancer pin[/dim]")
    else:
        _vprint("[dim]session: configured cookie[/dim]")
    return jar


def _unreadable_browser(browser: Browser, why: str) -> typer.Exit:
    """The error for a browser whose session could not be read, naming both ways out."""
    err.print(
        f"[red]no Overleaf session from {browser.value}: {why}[/red]\n"
        f"Sign into https://{overleaf_host()}/ there, try another browser with "
        "[bold]-b chrome|firefox|arc|brave|edge[/bold], or supply the cookie directly — "
        "[bold]overleaf.py export-env[/bold] prints the `export` lines for a host that has "
        "no browser of its own."
    )
    return typer.Exit(2)


def _glob(pattern: str) -> list[str]:
    """Every path matching an absolute `~`-relative glob, sorted."""
    expanded = Path(pattern).expanduser()
    root = Path(expanded.anchor)
    return sorted(str(path) for path in root.glob(str(expanded.relative_to(root))))


def _expand_brace_glob(pattern: str) -> list[str]:
    """Expand a one-brace glob like `{Default,Profile *}` into sorted matching paths.

    `Path.glob` has no brace alternation, and the browser stores need it: the default
    profile is `Default` while the rest are `Profile <n>`.
    """
    parts = _BRACE_ALTERNATION.match(pattern)
    if not parts:
        return _glob(pattern)
    prefix, suffix = parts["prefix"], parts["suffix"]
    return sorted(
        path for alt in parts["alts"].split(",") for path in _glob(f"{prefix}{alt}{suffix}")
    )


def _profile_cookie_files(browser: Browser) -> list[str]:
    """Every per-profile cookie database this browser has on this host."""
    return [
        path
        for pattern in _CHROMIUM_PROFILE_GLOBS.get(browser, ())
        for path in _expand_brace_glob(pattern)
    ]


def _load_cookies(
    loader, cookie_file: str | None, domain: str
) -> tuple[http.cookiejar.CookieJar | None, str | None]:
    """One profile's cookies for the domain, or the reason that profile could not be read.

    The reason is carried back rather than logged and dropped: when no profile is
    readable at all, a locked keyring must be distinguishable from "not signed in".
    """
    try:
        if cookie_file is None:
            return loader(domain_name=domain), None
        return loader(cookie_file=cookie_file, domain_name=domain), None
    except Exception as exc:  # each browser backend raises its own error type
        reason = f"{type(exc).__name__}: {exc}"
        _vprint(f"[dim]skipping {cookie_file or 'default store'}: {reason}[/dim]")
        return None, reason


def browser_cookies(browser: Browser) -> http.cookiejar.CookieJar:
    """The Overleaf cookies of the first browser profile that is signed in.

    A Chromium browser keeps one cookie store per profile, and a person with several
    profiles is typically signed into Overleaf in exactly one of them — so every profile
    is tried and the first holding a session wins, rather than only the default one.
    Cookies are never mixed across profiles: the load-balancer pin has to belong to the
    same session as the cookie it accompanies.
    """
    loader = getattr(browser_cookie3, browser.value, None)
    if loader is None:
        err.print(f"[red]browser_cookie3 has no reader for {browser.value}[/red]")
        raise typer.Exit(2)
    domain = overleaf_host().removeprefix("www.")
    profiles = _profile_cookie_files(browser)
    _vprint(f"[dim]{browser.value}: {len(profiles) or 'no'} profile store(s) to try[/dim]")
    last: http.cookiejar.CookieJar | None = None
    failure: str | None = None
    # `None` covers Firefox and Safari, whose stores browser_cookie3 locates itself.
    for cookie_file in profiles or [None]:
        jar, reason = _load_cookies(loader, cookie_file, domain)
        if jar is None:
            failure = reason
            continue
        last = jar
        if any(cookie.name == SESSION_COOKIE for cookie in jar):
            _vprint(f"[dim]signed in on {cookie_file or 'the default store'}[/dim]")
            return jar
    if last is None:
        raise _unreadable_browser(browser, failure or "no readable cookie store on this host")
    return last


def cookies() -> http.cookiejar.CookieJar:
    """The session jar: an explicitly configured cookie, else the browser's own store.

    The everyday case is "I am signed into Overleaf in my browser", so that works with no
    setup at all, the way the sibling slack CLI discovers its token. A supplied cookie
    still wins, since that is the only path on a machine with no browser.
    """
    if (jar := _configured_cookies()) is not None:
        return jar
    jar = browser_cookies(_BROWSER)
    if not any(cookie.name == SESSION_COOKIE for cookie in jar):
        raise _unreadable_browser(_BROWSER, f"its store holds no `{SESSION_COOKIE}` cookie")
    _vprint(f"[dim]session: {_BROWSER.value} cookie store[/dim]")
    return jar


def _session(jar: http.cookiejar.CookieJar) -> requests.Session:
    """A requests session carrying the cookies and a browser-shaped User-Agent."""
    http_session = requests.Session()
    # `update` copies the cookies across rather than swapping requests' own jar out, which
    # keeps the session's type intact and works with any CookieJar we hand it.
    http_session.cookies.update(jar)
    http_session.headers.update({"User-Agent": "Mozilla/5.0"})
    return http_session


_T = TypeVar("_T", bound=BaseModel)


def _url(path: str) -> str:
    return f"https://{overleaf_host()}{path}"


_HTML_ESCAPES = (
    ("&quot;", '"'),
    ("&#34;", '"'),
    ("&#39;", "'"),
    ("&lt;", "<"),
    ("&gt;", ">"),
    ("&amp;", "&"),
)


def page_metas(text: str) -> dict[str, str]:  # allow-dict: a name→raw-JSON index
    """Every `ol-*` meta tag on a page, name → unescaped content.

    Overleaf bootstraps its editor by serialising state into meta tags: the CSRF token,
    the project list, the current user. Reading them is how the page's own JavaScript
    gets that state, which makes it the stable surface rather than screen scraping.
    """
    out: dict[str, str] = {}
    for match in _META_CONTENT_RE.finditer(text):
        content = match.group("content")
        for escaped, plain in _HTML_ESCAPES:
            content = content.replace(escaped, plain)
        out[match.group("name")] = content
    return out


def _session_expired(what: str) -> typer.Exit:
    """The error every logged-out response funnels into, naming the fix."""
    err.print(
        f"[red]{what} — the session cookie is not logged in or has expired.[/red]\n"
        "Refresh it: sign into Overleaf in the browser and re-capture "
        f"`{SESSION_COOKIE}` into $OVERLEAF_SESSION_COOKIE."
    )
    return typer.Exit(2)


def _refused(what: str, status: int) -> typer.Exit:
    """The error for an outright refusal (401/403), which Overleaf's project routes answer
    an expired session with rather than a redirect — it has two causes, so name both."""
    err.print(
        f"[red]{what}: HTTP {status} — Overleaf refused the request.[/red]\n"
        f"Either the session cookie has expired (check with [bold]overleaf.py session[/bold], "
        f"then re-capture `{SESSION_COOKIE}`), or this account has no access to the project."
    )
    return typer.Exit(2)


def _require_ok(resp: requests.Response, what: str) -> None:
    """Exit on any non-200, routing a refusal through the session message."""
    if resp.status_code == 200:
        return
    if resp.status_code in (401, 403):
        raise _refused(what, resp.status_code)
    err.print(f"[red]{what}: HTTP {resp.status_code}[/red] {resp.text[:200]}")
    raise typer.Exit(2)


def _get_page(jar: http.cookiejar.CookieJar, path: str) -> dict[str, str]:  # allow-dict: meta index
    """Fetch an Overleaf HTML page and return its `ol-*` metas.

    A redirect is how Overleaf answers a logged-out request, so redirects are not
    followed: silently landing on the login page would otherwise read as an empty page.
    """
    resp = _session(jar).get(_url(path), timeout=30, allow_redirects=False)
    if resp.status_code in (301, 302, 303, 307, 308):
        raise _session_expired(f"{path} redirected to {resp.headers.get('location', '?')}")
    _require_ok(resp, path)
    return page_metas(resp.text)


def meta_model(metas: dict[str, str], name: str, model: type[_T]) -> _T:  # allow-dict: meta index
    """Parse one `ol-*` meta's JSON into `model`, failing loudly if Overleaf changes it."""
    raw = metas.get(name)
    if raw is None:
        err.print(
            f"[red]page carried no `ol-{name}` meta — Overleaf's page shape changed.[/red]\n"
            f"Found: {', '.join(sorted(metas)) or 'none'}"
        )
        raise typer.Exit(2)
    try:
        return model.model_validate_json(raw)
    except ValidationError as exc:
        err.print(f"[red]`ol-{name}` failed validation:[/red] {exc}")
        raise typer.Exit(2) from exc


def whoami_record(jar: http.cookiejar.CookieJar) -> OverleafUser:
    """The signed-in user, from `/user/personal_info`.

    Doubles as the session probe — a logged-out cookie never reaches a 200 here.
    """
    resp = _session(jar).get(
        _url("/user/personal_info"),
        headers={"Accept": "application/json"},
        timeout=30,
        allow_redirects=False,
    )
    if resp.status_code != 200:
        raise _session_expired(f"/user/personal_info: HTTP {resp.status_code}")
    try:
        return OverleafUser.model_validate(resp.json())
    except (ValidationError, ValueError) as exc:
        err.print(f"[red]/user/personal_info payload failed validation:[/red] {exc}")
        raise typer.Exit(2) from exc


def project_list(jar: http.cookiejar.CookieJar) -> ProjectsBlob:
    """Every project on the dashboard, from its prefetched blob."""
    return meta_model(_get_page(jar, "/project"), "prefetchedProjectsBlob", ProjectsBlob)


def _csrf_token(jar: http.cookiejar.CookieJar, path: str) -> str:
    """The CSRF token minted for this session, read off a page that carries one.

    Every mutating endpoint requires it echoed in `x-csrf-token`. Held for the life of the
    process, because Overleaf mints one per session and the page carrying it is a whole
    editor page: a `push` of two dozen files would otherwise load that page two dozen extra
    times. Never persisted between runs — a token outliving its session fails the write.
    """
    if (held := _CSRF_TOKENS.get(path)) is not None:
        return held
    token = _get_page(jar, path).get("csrfToken")
    if not token:
        err.print(f"[red]{path} carried no CSRF token[/red]")
        raise typer.Exit(2)
    _CSRF_TOKENS[path] = token
    return token


def _write_headers(
    jar: http.cookiejar.CookieJar, project_id: str
) -> dict[str, str]:  # allow-dict: header map
    """Headers Overleaf requires on a project write: CSRF, referer, JSON accept."""
    return {
        "x-csrf-token": _csrf_token(jar, f"/project/{project_id}"),
        "Referer": _url(f"/project/{project_id}"),
        "Accept": "application/json",
        "Cache-Control": "no-cache",
    }


def resolve_project(jar: http.cookiejar.CookieJar, ref: str) -> OverleafProject:
    """Resolve a project id, project URL, or name to exactly one project.

    An id or URL is taken as given, so it needs no dashboard fetch. A name is matched
    exactly, then case-insensitively, then by substring; an ambiguous name lists the
    candidates rather than picking one.
    """
    if match := (_PROJECT_ID_RE.match(ref) or _PROJECT_URL_RE.search(ref)):
        return OverleafProject(id=match.group("id"))
    live = [p for p in project_list(jar).projects if not p.trashed]
    matchers = (
        lambda project: project.name == ref,
        lambda project: project.name.casefold() == ref.casefold(),
        lambda project: ref.casefold() in project.name.casefold(),
    )
    for matches in matchers:
        hits = [project for project in live if matches(project)]
        if len(hits) == 1:
            return hits[0]
        if len(hits) > 1:
            listing = "\n".join(f"  {p.id}  {p.name}" for p in hits)
            err.print(f"[red]{ref!r} matches {len(hits)} projects — pass an id:[/red]\n{listing}")
            raise typer.Exit(2)
    err.print(
        f"[red]no project matches {ref!r}.[/red] Run [bold]overleaf.py projects list[/bold] for "
        "the names, or pass a project id or URL."
    )
    raise typer.Exit(2)


def _socket_frames(jar: http.cookiejar.CookieJar, project_id: str) -> Iterator[str]:
    """Yield socket.io frames for a project, closing the connection afterwards.

    The editor loads the file tree over socket.io and there is no HTTP endpoint that
    returns entity ids: `/project/<id>/entities` gives paths without them, while uploads
    and deletes both need one. So the tree comes from the `joinProjectResponse` frame the
    server pushes on connect. The framing is socket.io 0.9 text — `<type>:<ack>:<endpoint>:
    <payload>`, where type 5 is an event and 7 is an error.
    """
    from websocket import WebSocketConnectionClosedException, create_connection

    handshake = _session(jar).get(
        _url(f"/socket.io/1/?projectId={project_id}&t={int(time.time() * 1000)}"), timeout=30
    )
    if handshake.status_code != 200:
        raise _session_expired(f"socket.io handshake: HTTP {handshake.status_code}")
    socket_id = handshake.text.split(":")[0]
    cookie_header = "; ".join(f"{cookie.name}={cookie.value}" for cookie in jar)
    connection = create_connection(
        f"wss://{overleaf_host()}/socket.io/1/websocket/{socket_id}?projectId={project_id}",
        header=[f"Cookie: {cookie_header}", "User-Agent: Mozilla/5.0"],
        origin=f"https://{overleaf_host()}",
        timeout=30,
    )
    try:
        while True:
            # socket.io 0.9 frames are text, but the transport may hand back a binary
            # frame; decoding here keeps every consumer dealing in strings.
            try:
                frame = connection.recv()
            except WebSocketConnectionClosedException:
                # The server hung up — how it ends a rejected connection. The stream simply
                # ends; the consumer decides what an early end means.
                return
            yield frame if isinstance(frame, str) else frame.decode("utf-8", errors="replace")
    finally:
        connection.close()


def project_tree(jar: http.cookiejar.CookieJar, project_id: str) -> ProjectTree:
    """Connect as the editor does and parse the project tree it is handed."""
    for frame in _socket_frames(jar, project_id):
        if frame.startswith("7:"):
            err.print(
                f"[red]socket refused project {project_id} ({frame.strip()}) — no access to it, "
                "or the session expired.[/red]"
            )
            raise typer.Exit(2)
        if not frame.startswith("5:"):
            continue
        payload = json.loads(frame[len("5:") :].lstrip(":"))
        if payload.get("name") == "connectionRejected":
            # How Overleaf's real-time router refuses a join — an invalid session or a
            # project this account cannot read — before it hangs up.
            args = payload.get("args") or [{}]
            reason = args[0].get("message", "?") if isinstance(args[0], dict) else "?"
            err.print(
                f"[red]socket rejected project {project_id} ({reason}) — the session cookie "
                "has expired, or this account has no access to the project.[/red]"
            )
            raise typer.Exit(2)
        if payload.get("name") != "joinProjectResponse":
            continue
        root = payload["args"][0]["project"]["rootFolder"][0]
        return ProjectTree(root_folder_id=root["_id"], entities=list(walk_folder(root, prefix="")))
    err.print(f"[red]socket closed before sending project {project_id}'s file tree[/red]")
    raise typer.Exit(2)


def walk_folder(
    folder: dict, *, prefix: str
) -> Iterator[RemoteEntity]:  # allow-dict: raw socket JSON
    """Flatten a `rootFolder` node into path-keyed entities, depth first.

    The socket payload is Overleaf's own nested JSON rather than a surface of ours, so it
    is read positionally here and converted once; everything downstream sees only
    `RemoteEntity`.
    """
    for doc in folder.get("docs", []):
        yield RemoteEntity(path=f"{prefix}{doc['name']}", id=doc["_id"], kind="doc")
    for file_ref in folder.get("fileRefs", []):
        yield RemoteEntity(path=f"{prefix}{file_ref['name']}", id=file_ref["_id"], kind="file")
    for child in folder.get("folders", []):
        path = f"{prefix}{child['name']}"
        yield RemoteEntity(path=path, id=child["_id"], kind="folder")
        yield from walk_folder(child, prefix=f"{path}/")


def read_entity(jar: http.cookiejar.CookieJar, project_id: str, entity: RemoteEntity) -> bytes:
    """One doc's or file's current bytes, over HTTP.

    Text and binary entities live behind different routes; both are plain authenticated
    GETs, so neither needs the socket.
    """
    path = (
        f"/Project/{project_id}/doc/{entity.id}/download"
        if entity.kind == "doc"
        else f"/project/{project_id}/file/{entity.id}"
    )
    resp = _session(jar).get(_url(path), timeout=60)
    _require_ok(resp, f"reading {entity.path}")
    return resp.content


def upload_file(
    jar: http.cookiejar.CookieJar,
    project_id: str,
    tree: ProjectTree,
    remote_path: str,
    content: bytes,
) -> UploadedEntity:
    """Create or replace one file at `remote_path`, creating parent folders as needed.

    This is the editor's own folder-drop upload: the file posts to the root folder with
    its `relativePath`, and Overleaf walks that path server-side, creating any missing
    folder. An entity already at the path is replaced in place, keeping its id and the
    project's history, which is what makes a repeated push idempotent.
    """
    name = remote_path.rsplit("/", 1)[-1]
    parent = remote_path.rsplit("/", 1)[0] if "/" in remote_path else ""
    mime = guess_type(name)[0] or "application/octet-stream"
    resp = _session(jar).post(
        _url(f"/project/{project_id}/upload"),
        params={"folder_id": tree.root_folder_id},
        files={
            # Uppy, the editor's uploader, sends the string "null" for a root-level file.
            "relativePath": (None, f"{parent}/{name}" if parent else "null"),
            "name": (None, name),
            "type": (None, mime),
            "qqfile": (name, content, mime),
        },
        headers=_write_headers(jar, project_id),
        timeout=180,
    )
    if resp.status_code != 200:
        err.print(f"[red]uploading {remote_path}: HTTP {resp.status_code}[/red] {resp.text[:200]}")
        raise typer.Exit(2)
    result = UploadedEntity.model_validate(resp.json())
    if not result.success:
        err.print(f"[red]uploading {remote_path} failed:[/red] {result.error or 'unknown error'}")
        raise typer.Exit(2)
    return result


def delete_entity(jar: http.cookiejar.CookieJar, project_id: str, entity: RemoteEntity) -> None:
    """Delete one doc, file, or folder from a project."""
    resp = _session(jar).delete(
        _url(f"/project/{project_id}/{entity.kind}/{entity.id}"),
        json={},
        headers=_write_headers(jar, project_id),
        timeout=60,
    )
    if resp.status_code not in (200, 204):
        err.print(f"[red]deleting {entity.path}: HTTP {resp.status_code}[/red] {resp.text[:200]}")
        raise typer.Exit(2)


def local_files(directory: Path) -> dict[str, Path]:  # allow-dict: a path→path index
    """Every file under `directory`, keyed by its Overleaf-relative path.

    Dot-prefixed names are skipped at every level: a staging directory routinely carries
    `.git`, `.DS_Store`, and editor state that has no business in a paper project.
    """
    out: dict[str, Path] = {}
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory)
        if any(part.startswith(".") for part in relative.parts):
            continue
        if path.is_file():
            out[relative.as_posix()] = path
    return out


def same_content(remote: bytes, local: bytes) -> bool:
    """Whether two versions of a file are the same, ignoring the trailing newline.

    Overleaf stores a text doc as a line array and rebuilds it on download, which can add
    or drop the final newline with no edit having happened. Treating that as a change
    would make every text file push on every run.
    """
    return remote.rstrip(b"\n") == local.rstrip(b"\n")


def plan_push(
    jar: http.cookiejar.CookieJar,
    project_id: str,
    tree: ProjectTree,
    local: dict[str, Path],  # allow-dict: a path→path index
    *,
    prune: bool,
) -> PushPlan:
    """Diff a local directory against the project, comparing content to skip no-ops.

    A path on both sides is downloaded and compared, so an unchanged directory pushes
    nothing and leaves the project's history alone.
    """
    remote = tree.by_path()
    plan = PushPlan()
    for relative, path in local.items():
        entity = remote.get(relative)
        if entity is None or entity.kind == "folder":
            plan.added.append(relative)
        elif same_content(read_entity(jar, project_id, entity), path.read_bytes()):
            plan.unchanged.append(relative)
        else:
            plan.replaced.append(relative)
    if prune:
        plan.pruned = [entity for entity in tree.files() if entity.path not in local]
    return plan


def _render_plan(
    console: Console, plan: PushPlan, *, project: OverleafProject, prune: bool
) -> None:
    """Print the push plan, one line per changed path."""
    console.print(f"[bold]{project.label}[/bold] [dim]{project.url}[/dim]")
    for label, colour, paths in (
        ("add", "green", plan.added),
        ("replace", "yellow", plan.replaced),
    ):
        for path in sorted(paths):
            console.print(f"  [{colour}]{label:>7}[/{colour}]  {path}")
    for entity in plan.pruned:
        console.print(f"  [red]{'delete':>7}[/red]  {entity.path}")
    console.print(f"  [dim]{len(plan.unchanged)} unchanged[/dim]")
    if not prune:
        console.print("  [dim]--prune off: project files the directory lacks are left alone[/dim]")


@app.command()
def session() -> None:
    """Print the signed-in account — the quickest check that the session still works."""
    user = whoami_record(cookies())
    Console().print(f"[bold]{user.label}[/bold] [dim]{user.id or '?'}[/dim] on {overleaf_host()}")


@projects_app.command("list")
def projects_list(
    include_archived: bool = typer.Option(False, "--archived", help="Include archived projects."),
    as_json: bool = typer.Option(False, "--json", help="Emit the raw project records."),
) -> None:
    """List your projects with their ids."""
    projects = [
        project
        for project in project_list(cookies()).projects
        if not project.trashed and (include_archived or not project.archived)
    ]
    if as_json:
        print(json.dumps([project.model_dump(mode="json") for project in projects], indent=2))
        return
    console = Console()
    for project in sorted(projects, key=lambda p: p.last_updated or "", reverse=True):
        owner = project.owner.label if project.owner else "?"
        console.print(f"{project.id}  [bold]{project.name}[/bold]  [dim]{owner}[/dim]")
    console.print(f"[dim]{len(projects)} project(s)[/dim]")


@projects_app.command("new")
def projects_new(
    name: str = typer.Argument(..., help="Project name, as it will appear on the dashboard."),
) -> None:
    """Create an empty project and print its id and URL."""
    jar = cookies()
    # The dashboard mints the CSRF token this POST needs; there is no project id yet.
    resp = _session(jar).post(
        _url("/project/new"),
        json=NewProjectReq(projectName=name).model_dump(),
        headers={
            "x-csrf-token": _csrf_token(jar, "/project"),
            "Referer": _url("/project"),
            "Accept": "application/json",
        },
        timeout=60,
    )
    if resp.status_code != 200:
        err.print(f"[red]/project/new: HTTP {resp.status_code}[/red] {resp.text[:200]}")
        raise typer.Exit(2)
    created = NewProject.model_validate(resp.json())
    url = f"https://{overleaf_host()}/project/{created.project_id}"
    Console().print(f"{created.project_id}  [dim]{url}[/dim]")


@files_app.command("ls")
def files_ls(
    project: str = typer.Argument(..., help="Project id, URL, or name."),
    as_json: bool = typer.Option(False, "--json", help="Emit path/id/kind records."),
) -> None:
    """List a project's docs, files, and folders with their entity ids."""
    jar = cookies()
    tree = project_tree(jar, resolve_project(jar, project).id)
    if as_json:
        print(tree.model_dump_json(indent=2))
        return
    console = Console()
    for entity in sorted(tree.entities, key=lambda e: e.path):
        suffix = "/" if entity.kind == "folder" else ""
        console.print(f"[dim]{entity.kind:>6}[/dim]  {entity.path}{suffix}")


def _require_file(tree: ProjectTree, project: OverleafProject, path: str) -> RemoteEntity:
    """The doc or file at `path`, refusing a folder or a miss."""
    entity = tree.by_path().get(path)
    if entity is None or entity.kind == "folder":
        err.print(f"[red]{path!r} is not a file in {project.label}[/red]")
        raise typer.Exit(2)
    return entity


@files_app.command("read")
def files_read(
    project: str = typer.Argument(..., help="Project id, URL, or name."),
    path: str = typer.Argument(..., help="Path inside the project, e.g. sections/intro.tex"),
    out: Path | None = typer.Option(None, "--out", "-o", help="Write here instead of stdout."),
) -> None:
    """Print (or save) one file's current content from the project."""
    jar = cookies()
    resolved = resolve_project(jar, project)
    tree = project_tree(jar, resolved.id)
    content = read_entity(jar, resolved.id, _require_file(tree, resolved, path))
    if out is None:
        sys.stdout.buffer.write(content)
        return
    out.write_bytes(content)
    err.print(f"[green]wrote {len(content):,} bytes to {out}[/green]")


@files_app.command("write")
def files_write(
    project: str = typer.Argument(..., help="Project id, URL, or name."),
    path: str = typer.Argument(..., help="Destination path inside the project."),
    source: Path = typer.Option(..., "--from", "-f", help="Local file to upload."),
    yes: bool = typer.Option(False, "--yes", "-y", help="Skip the confirmation prompt."),
) -> None:
    """Upload one local file, replacing whatever is at that path."""
    if not source.is_file():
        err.print(f"[red]{source} is not a file[/red]")
        raise typer.Exit(2)
    jar = cookies()
    resolved = resolve_project(jar, project)
    tree = project_tree(jar, resolved.id)
    existing = tree.by_path().get(path)
    verb = "replace" if existing is not None and existing.kind != "folder" else "add"
    err.print(f"{verb} [bold]{path}[/bold] in {resolved.label} from {source}")
    if not yes:
        typer.confirm("Push it?", abort=True)
    upload_file(jar, resolved.id, tree, path, source.read_bytes())
    done = "replaced" if verb == "replace" else "added"
    err.print(f"[green]{done} {path}[/green] {resolved.url}")


@files_app.command("rm")
def files_rm(
    project: str = typer.Argument(..., help="Project id, URL, or name."),
    path: str = typer.Argument(..., help="Path inside the project to delete."),
    yes: bool = typer.Option(False, "--yes", "-y", help="Skip the confirmation prompt."),
) -> None:
    """Delete one doc, file, or folder from a project."""
    jar = cookies()
    resolved = resolve_project(jar, project)
    tree = project_tree(jar, resolved.id)
    entity = tree.by_path().get(path)
    if entity is None:
        err.print(f"[red]{path!r} is not in {resolved.label}[/red]")
        raise typer.Exit(2)
    err.print(f"delete {entity.kind} [bold]{path}[/bold] from {resolved.label}")
    if not yes:
        typer.confirm("Delete it?", abort=True)
    delete_entity(jar, resolved.id, entity)
    err.print(f"[green]deleted {path}[/green]")


@app.command()
def push(
    project: str = typer.Argument(..., help="Project id, URL, or name."),
    directory: Path = typer.Argument(..., help="Local directory to mirror into the project."),
    prune: bool = typer.Option(False, "--prune", help="Delete project files the directory lacks."),
    dry_run: bool = typer.Option(False, "--dry-run", help="Show the plan; change nothing."),
    yes: bool = typer.Option(False, "--yes", "-y", help="Skip the confirmation prompt."),
) -> None:
    """Mirror a local directory into a project, uploading only what changed."""
    if not directory.is_dir():
        err.print(f"[red]{directory} is not a directory[/red]")
        raise typer.Exit(2)
    local = local_files(directory)
    if not local:
        err.print(f"[red]{directory} holds no files to push[/red]")
        raise typer.Exit(2)
    jar = cookies()
    resolved = resolve_project(jar, project)
    tree = project_tree(jar, resolved.id)
    plan = plan_push(jar, resolved.id, tree, local, prune=prune)
    console = Console()
    _render_plan(console, plan, project=resolved, prune=prune)
    if plan.is_empty():
        console.print("[green]project already matches the directory — nothing to push[/green]")
        return
    if dry_run:
        console.print("[dim]dry run — nothing uploaded[/dim]")
        return
    if not yes:
        typer.confirm("Push it?", abort=True)
    _apply_push(console, jar, resolved, tree, plan, local)


def _apply_push(
    console: Console,
    jar: http.cookiejar.CookieJar,
    project: OverleafProject,
    tree: ProjectTree,
    plan: PushPlan,
    local: dict[str, Path],  # allow-dict: a path→path index
) -> None:
    """Upload every planned write, then delete every planned prune."""
    for relative in plan.writes:
        upload_file(jar, project.id, tree, relative, local[relative].read_bytes())
        console.print(f"  [green]pushed[/green]   {relative}")
    for entity in plan.pruned:
        delete_entity(jar, project.id, entity)
        console.print(f"  [red]deleted[/red]  {entity.path}")
    console.print(
        f"[green]{len(plan.writes)} pushed, {len(plan.pruned)} deleted[/green] {project.url}"
    )


@app.command("compile")
def compile_project(
    project: str = typer.Argument(..., help="Project id, URL, or name."),
    pdf: Path | None = typer.Option(None, "--pdf", help="Save the compiled PDF here."),
    logs: bool = typer.Option(False, "--logs", help="Print the LaTeX log."),
) -> None:
    """Compile a project on Overleaf, reporting the status and optionally saving the PDF."""
    jar = cookies()
    resolved = resolve_project(jar, project)
    resp = _session(jar).post(
        _url(f"/project/{resolved.id}/compile"),
        json=CompileReq().model_dump(),
        headers=_write_headers(jar, resolved.id),
        timeout=600,
    )
    if resp.status_code != 200:
        err.print(f"[red]compile: HTTP {resp.status_code}[/red] {resp.text[:200]}")
        raise typer.Exit(2)
    result = CompileResult.model_validate(resp.json())
    console = Console()
    colour = "green" if result.status == "success" else "red"
    console.print(f"compile [{colour}]{result.status}[/{colour}] [dim]{resolved.url}[/dim]")
    if logs or result.status != "success":
        _print_log(console, jar, result)
    if pdf is not None:
        _save_pdf(jar, result, pdf)
    if result.status != "success":
        raise typer.Exit(1)


def _artefact_bytes(
    jar: http.cookiejar.CookieJar, result: CompileResult, artefact: CompileOutputFile
) -> bytes:
    """Download one compile artefact from the URL the compile response gave for it.

    The URL is a bare path; the backend pin travels as `clsiserverid`, exactly as the
    editor sends it, because the web tier forwards only that query value to the CLSI.
    """
    params = {"clsiserverid": result.clsi_server_id} if result.clsi_server_id else None
    resp = _session(jar).get(_url(artefact.url or ""), params=params, timeout=120)
    _require_ok(resp, artefact.path)
    return resp.content


def _print_log(console: Console, jar: http.cookiejar.CookieJar, result: CompileResult) -> None:
    """Print the compile's LaTeX log, or say that it produced none."""
    artefact = result.artefact(".log")
    if artefact is None or not artefact.url:
        console.print("[yellow]no log among the output files[/yellow]")
        return
    console.print(_artefact_bytes(jar, result, artefact).decode("utf-8", errors="replace"))


def _save_pdf(jar: http.cookiejar.CookieJar, result: CompileResult, dest: Path) -> None:
    """Save the compiled PDF, refusing when the compile produced none."""
    artefact = result.artefact(".pdf")
    if artefact is None or not artefact.url:
        err.print("[red]compile produced no PDF — rerun with --logs to see why[/red]")
        raise typer.Exit(1)
    content = _artefact_bytes(jar, result, artefact)
    dest.write_bytes(content)
    err.print(f"[green]wrote {len(content):,} bytes to {dest}[/green]")


@app.command()
def download(
    project: str = typer.Argument(..., help="Project id, URL, or name."),
    out: Path | None = typer.Option(None, "--out", "-o", help="Zip path; default <name>.zip"),
) -> None:
    """Download a whole project as a zip."""
    jar = cookies()
    resolved = resolve_project(jar, project)
    resp = _session(jar).get(_url(f"/project/{resolved.id}/download/zip"), timeout=300)
    _require_ok(resp, "download")
    dest = out or Path(f"{resolved.label}.zip")
    dest.write_bytes(resp.content)
    err.print(f"[green]wrote {len(resp.content):,} bytes to {dest}[/green]")


@app.command("export-env")
def export_env() -> None:
    """Print `export` lines carrying this browser's session, for a host that has none.

    Run on the machine holding the Overleaf login and eval the output where the CLI needs
    to run — a server, a container, an ssh session whose keyring is unreachable. The
    session is validated before it is printed, so a dead cookie is never shipped onward.
    """
    jar = browser_cookies(_BROWSER)
    session = next((c.value for c in jar if c.name == SESSION_COOKIE), "")
    if not session:
        raise _unreadable_browser(_BROWSER, f"its store holds no `{SESSION_COOKIE}` cookie")
    user = whoami_record(jar)
    err.print(f"[dim]session for {user.label} on {overleaf_host()} (from {_BROWSER.value})[/dim]")
    print(f"export OVERLEAF_SESSION_COOKIE={shlex.quote(session)}")
    if sticky := next((c.value for c in jar if c.name == STICKY_COOKIE), ""):
        print(f"export OVERLEAF_GCLB_COOKIE={shlex.quote(sticky)}")
    if overleaf_host() != DEFAULT_HOST:
        print(f"export OVERLEAF_HOST={shlex.quote(overleaf_host())}")


if __name__ == "__main__":
    app()
