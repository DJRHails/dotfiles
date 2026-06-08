#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.13"
# dependencies = [
#   "google-api-python-client",
#   "google-auth",
#   "python-frontmatter",
#   "loguru",
# ]
# ///
"""Bidirectional sync between a Slidev markdown deck and Google Slides.

`push` builds **native** Slides objects (title/body placeholders, bullets,
tables, positioned images) via `presentations.batchUpdate` — so text stays
editable, not a flat image. `pull` reconstructs Slidev markdown from those
native objects. `roundtrip` pushes a sample into a fresh deck, pulls it back,
and asserts the two are semantically identical.

Auth is borrowed from `gog` (no separate OAuth client): the client id/secret
live in `~/Library/Application Support/gogcli/credentials.json` and the refresh
token is exported via `gog auth tokens export`. The stored token already carries
the `slides`+`drive` scopes.

Idempotent sync (upsert), never a blind append:

- Each managed slide is created with `objectId = s2g_<keyHash>_<contentHash>`.
- `keyHash` identifies *which* slide (per-slide `id:` frontmatter, else a title
  slug, else index) and survives edits/reorders; `contentHash` is over a
  canonical render, so push->pull->push is a no-op.
- Diff: identical hash -> skip; same key, new content -> replace; new key ->
  create. Removed slides are kept by default (`--prune` to delete).
- Only `s2g_`-prefixed slides are ever touched; hand-authored slides are
  invisible to the sync. A tiny `<!-- s2g {...} -->` marker in speaker notes
  carries the human id + image path so `pull` can recover them.

Usage:
    bin/slidesync.py push deck.slidev.md --deck <id> [--anchor <slideId>] [--prune]
    bin/slidesync.py push deck.slidev.md --new "My Talk"
    bin/slidesync.py pull <id> --out deck.slidev.md
    bin/slidesync.py roundtrip [--keep]
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

import frontmatter
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from loguru import logger

GOGCLI_CRED = Path.home() / "Library/Application Support/gogcli/credentials.json"
TOKEN_URI = "https://oauth2.googleapis.com/token"
SCOPES = [
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/drive",
]
DEFAULT_ACCOUNT = None  # resolved from gog (or $SLIDESYNC_ACCOUNT)
IMAGE_CACHE = Path(".data/cache/slidesync_images.json")

MANAGED_RE = re.compile(r"^s2g_[0-9a-f]{10}_[0-9a-f]{10}$")
MARKER_RE = re.compile(r"<!--\s*s2g\s*(?P<json>\{.*?\})\s*-->", re.S)
TEMPLATE_TAG_RE = re.compile(r"<!--\s*s2g:template\s+(?P<name>\S+)\s*-->")
EMU_PER_PX = 9525  # 96 dpi
EMU_PER_IN = 914400
SLIDE_W = 9144000
SLIDE_H = 5143500  # 16:9 slide height (5.625in)
BODY_X, BODY_Y = 457200, 1143000
BODY_W, BODY_H = 8229600, 3771900

SECTION_LAYOUTS = {"section", "center", "cover", "intro"}
RESERVED_KEYS = {"id", "template", "layout"}

# Brand palette extracted from the Reliable Monitors deck (IBM Plex Sans).
BRAND_FONT = "IBM Plex Sans"
RED = {"red": 0.7529412, "green": 0.22352941, "blue": 0.16862746}   # #C0392B
INK = {"red": 0.011764706, "green": 0.02745098, "blue": 0.07058824}  # #03070F
BODY_INK = {"red": 0.11764706, "green": 0.1254902, "blue": 0.14117648}  # #1E2024
PAPER = {"red": 0.98039216, "green": 0.98039216, "blue": 0.98039216}  # #FAFAFA
LIGHT_BG, DARK_BG = PAPER, BODY_INK

# ---------------------------------------------------------------------------
# Auth (borrowed from gog)
# ---------------------------------------------------------------------------


def get_services(account: str | None):
    creds = _credentials(account or _default_account())
    slides = build("slides", "v1", credentials=creds, cache_discovery=False)
    drive = build("drive", "v3", credentials=creds, cache_discovery=False)
    return slides, drive


def _default_account() -> str:
    """Resolve the gog account: $SLIDESYNC_ACCOUNT, else gog's default account."""
    env = os.environ.get("SLIDESYNC_ACCOUNT")
    if env:
        return env
    out = subprocess.run(["gog", "auth", "list", "-p"], capture_output=True,
                         text=True).stdout
    rows = [ln.split("\t") for ln in out.splitlines() if ln.strip()]
    for cols in rows:
        if len(cols) >= 2 and cols[1] == "default":
            return cols[0]
    if rows:
        return rows[0][0]
    sys.exit("no gog account found; run `gog login <email>` or set "
             "$SLIDESYNC_ACCOUNT")


def _credentials(account: str) -> Credentials:
    if not GOGCLI_CRED.exists():
        sys.exit(f"gog OAuth client not found at {GOGCLI_CRED}")
    client = json.loads(GOGCLI_CRED.read_text())
    with tempfile.NamedTemporaryFile(suffix=".json") as tmp:
        subprocess.run(
            ["gog", "auth", "tokens", "export", account, "--out", tmp.name,
             "--overwrite"],
            check=True, capture_output=True, text=True,
        )
        token = json.loads(Path(tmp.name).read_text())
    creds = Credentials(
        token=None, refresh_token=token["refresh_token"],
        client_id=client["client_id"], client_secret=client["client_secret"],
        token_uri=TOKEN_URI, scopes=SCOPES,
    )
    creds.refresh(Request())
    return creds


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------


@dataclass
class Run:
    start: int  # codepoint offset into Para.text
    end: int
    style: str  # bold | italic | code | link
    link: str | None = None


@dataclass
class Para:
    text: str  # clean text, no leading tabs
    runs: list[Run] = field(default_factory=list)
    depth: int = -1  # >=0 bullet nesting; -1 plain paragraph
    ordered: bool = False  # numbered list item (1.) vs bullet (-)


@dataclass
class Slide:
    key: str
    layout: str  # section | content | image | table (generative path)
    title: str = ""
    paras: list[Para] = field(default_factory=list)
    image: str | None = None
    table: list[list[str]] | None = None
    notes: str = ""
    kicker: str = ""  # h2 above an h1 -> {{h2}} kicker
    layout_name: str | None = None  # explicit `layout:` — section kw or theme layout
    template_name: str | None = None  # explicit `template:` — tagged styled slide
    vars: dict = field(default_factory=dict)  # extra frontmatter -> {{token}} values
    key_hash: str = ""
    content_hash: str = ""
    object_id: str = ""

    def semantic(self) -> tuple:
        def runs(p):
            return tuple((r.start, r.end, r.style, r.link) for r in p.runs)
        paras = tuple((p.depth, p.ordered, p.text, runs(p)) for p in self.paras)
        table = tuple(map(tuple, self.table)) if self.table else None
        return (self.key, self.layout_name, self.template_name,
                tuple(sorted(self.vars.items())), self.layout, self.title,
                self.kicker, paras, table, self.image, self.notes)


def _u16(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def _sha10(text: str) -> str:
    return hashlib.sha1(text.encode()).hexdigest()[:10]


# ---------------------------------------------------------------------------
# Importer:  markdown -> Slide
# ---------------------------------------------------------------------------

VCLICK_RE = re.compile(r"</?v-clicks?\b[^>]*>", re.I)
DIV_RE = re.compile(r"</?(?:div|span)\b[^>]*>", re.I)
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
LIST_RE = re.compile(r"^(?P<indent>\s*)(?P<marker>[-*]|\d+\.)\s+(?P<text>.*)$")
IMAGE_RE = re.compile(r"^!\[(?P<alt>[^\]]*)\]\((?P<url>[^)]+)\)\s*$")
COMMENT_RE = re.compile(r"<!--(?P<body>.*?)-->", re.S)
TABLE_SEP_RE = re.compile(r"^\s*\|?[\s:|-]+\|?\s*$")
INLINE_RE = re.compile(
    r"""(?x)
    (\*\*.+?\*\* | __.+?__
     | \*[^*]+?\* | _[^_]+?_
     | `[^`]+?`
     | \[[^\]]+?\]\([^)]+?\))
    """
)


def load_slides(path: Path) -> list[Slide]:
    return build_slides(split_slides(path.read_text()))


def split_slides(text: str) -> list[tuple[dict, str]]:
    post = frontmatter.loads(text)
    chunks = re.split(r"(?m)^---[ \t]*$", post.content)
    out: list[tuple[dict, str]] = []
    i = 0
    while i < len(chunks):
        meta, chunk = {}, chunks[i]
        if i + 1 < len(chunks) and _is_yaml_block(chunk):
            meta = _parse_yaml(chunk)
            i += 1
            chunk = chunks[i] if i < len(chunks) else ""
        if chunk.strip():
            out.append((meta, chunk))
        i += 1
    return out


def _is_yaml_block(chunk: str) -> bool:
    lines = [ln for ln in chunk.splitlines() if ln.strip()]
    return bool(lines) and all(re.match(r"^\s*[\w-]+\s*:", ln) for ln in lines)


def _parse_yaml(text: str) -> dict:
    out = {}
    for line in text.splitlines():
        m = re.match(r"^\s*([\w-]+)\s*:\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip("'\"")
    return out


def build_slides(chunks: list[tuple[dict, str]]) -> list[Slide]:
    return [build_slide(meta, body, i) for i, (meta, body) in enumerate(chunks)]


def build_slide(meta: dict, body: str, index: int) -> Slide:
    headings, paras, image, table, notes = parse_body(body)
    h1, h2 = headings.get(1), headings.get(2)
    title = h1 or h2 or ""           # h1 is the headline; a lone h2 is the title
    kicker = h2 if (h1 and h2) else ""  # an h2 above an h1 is the kicker
    key = meta.get("id") or _slug(title) or f"slide{index}"
    slide = Slide(key, _layout_of(meta, image, table), title, paras, image,
                  table, notes)
    slide.kicker = kicker
    slide.layout_name = meta.get("layout")
    slide.template_name = meta.get("template")
    slide.vars = {k: v for k, v in meta.items() if k not in RESERVED_KEYS}
    return _finalize(slide)


def _finalize(slide: Slide) -> Slide:
    slide.key_hash = _sha10(slide.key)
    slide.content_hash = _sha10(to_slidev(slide, include_id=False))
    slide.object_id = f"s2g_{slide.key_hash}_{slide.content_hash}"
    return slide


def _layout_of(meta: dict, image, table) -> str:
    if meta.get("layout") in SECTION_LAYOUTS:
        return "section"
    if image:
        return "image"
    if table:
        return "table"
    return "content"


def parse_body(body: str):
    """Return (headings{level:text}, paras, image, table, notes)."""
    notes = _extract_notes(body)
    body = COMMENT_RE.sub("", body)
    body = VCLICK_RE.sub("", DIV_RE.sub("", body))
    lines = body.splitlines()
    headings, paras, image, table = {}, [], None, None
    i = 0
    while i < len(lines):
        line, stripped = lines[i], lines[i].strip()
        if not stripped:
            if paras and (paras[-1].text or paras[-1].depth >= 0):
                paras.append(Para("", [], -1))  # keep one blank line for spacing
            i += 1
            continue
        hm = HEADING_RE.match(line)
        level = len(hm.group(1)) if hm else 0
        if hm and level in (1, 2) and level not in headings and not paras:
            headings[level] = parse_inline(hm.group(2).strip())[0]
            i += 1
        elif (im := IMAGE_RE.match(stripped)):
            image, i = im.group("url"), i + 1
        elif "|" in line and i + 1 < len(lines) and TABLE_SEP_RE.match(lines[i + 1]):
            table, i = _parse_table(lines, i)
        else:
            paras.append(_parse_para(line, hm))
            i += 1
    while paras and not paras[-1].text and paras[-1].depth < 0 \
            and not paras[-1].runs:
        paras.pop()
    return headings, paras, image, table, notes


def _extract_notes(body: str) -> str:
    parts = [m.group("body").strip() for m in COMMENT_RE.finditer(body)]
    joined = "\n".join(p for p in parts if p)
    return MARKER_RE.sub("", joined).strip()


def _parse_para(line: str, hm) -> Para:
    lm = LIST_RE.match(line)
    if lm:
        depth = len(lm.group("indent").replace("\t", "  ")) // 2
        clean, runs = parse_inline(lm.group("text").strip())
        return Para(clean, runs, depth, ordered=lm.group("marker")[0].isdigit())
    if hm:
        clean, _ = parse_inline(hm.group(2).strip())
        return Para(clean, [Run(0, len(clean), "bold")], -1)
    clean, runs = parse_inline(line.strip())
    return Para(clean, runs, -1)


def _parse_table(lines, i):
    rows = []
    while i < len(lines) and "|" in lines[i]:
        if TABLE_SEP_RE.match(lines[i]):
            i += 1
            continue
        cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
        rows.append([parse_inline(c)[0] for c in cells])
        i += 1
    return rows, i


WIKILINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]")
BR_RE = re.compile(r"<br\s*/?>", re.I)


def _clean_text(text: str) -> str:
    text = BR_RE.sub(" ", text)
    text = WIKILINK_RE.sub(lambda m: m.group(2) or m.group(1), text)
    return html.unescape(text)


def parse_inline(text: str) -> tuple[str, list[Run]]:
    text = _clean_text(text)
    clean, runs, pos = "", [], 0
    for m in INLINE_RE.finditer(text):
        clean += text[pos:m.start()]
        inner, style, link = _inline_inner(m.group(0))
        runs.append(Run(len(clean), len(clean) + len(inner), style, link))
        clean += inner
        pos = m.end()
    clean += text[pos:]
    return clean, runs


def _inline_inner(tok: str):
    if tok.startswith(("**", "__")):
        return tok[2:-2], "bold", None
    if tok.startswith("`"):
        return tok[1:-1], "code", None
    if tok.startswith("["):
        m = re.match(r"\[([^\]]+)\]\(([^)]+)\)", tok)
        return m.group(1), "link", m.group(2)
    return tok[1:-1], "italic", None


# ---------------------------------------------------------------------------
# Canonical render:  Slide -> markdown
# ---------------------------------------------------------------------------

MARKS = {"bold": ("**", "**"), "italic": ("*", "*"), "code": ("`", "`")}


def to_slidev(slide: Slide, include_id: bool = True) -> str:
    fm = {}
    if slide.template_name:
        fm["template"] = slide.template_name
        for k in sorted(slide.vars):
            fm[k] = slide.vars[k]
    elif slide.layout_name:
        fm["layout"] = slide.layout_name
    if include_id:
        fm["id"] = slide.key
    out = []
    if fm:
        out += ["---"] + [f"{k}: {v}" for k, v in fm.items()] + ["---"]
    if slide.kicker:  # h1 headline + h2 kicker
        out.append("# " + slide.title)
        out.append("## " + slide.kicker)
    elif slide.title:
        out.append(("# " if slide.layout == "section" else "## ") + slide.title)
    out += [_render_para(p) for p in slide.paras]
    if slide.image:
        out.append(f"![]({slide.image})")
    if slide.table:
        out += _render_table(slide.table)
    if slide.notes:
        out.append(f"<!-- {slide.notes} -->")
    return "\n".join(out).strip() + "\n"


def _render_para(p: Para) -> str:
    body = render_inline(p.text, p.runs)
    if p.depth >= 0:
        return "  " * p.depth + ("1. " if p.ordered else "- ") + body
    return body


def render_inline(text: str, runs: list[Run]) -> str:
    edits = []
    for r in runs:
        if r.style == "link":
            edits.append((r.start, "["))
            edits.append((r.end, f"]({r.link})"))
        else:
            o, c = MARKS[r.style]
            edits.append((r.start, o))
            edits.append((r.end, c))
    out, last = [], 0
    for pos, mark in sorted(edits, key=lambda e: (e[0], e[1] in (")",))):
        out.append(text[last:pos])
        out.append(mark)
        last = pos
    out.append(text[last:])
    return "".join(out)


def _render_table(table) -> list[str]:
    head = "| " + " | ".join(table[0]) + " |"
    sep = "| " + " | ".join("---" for _ in table[0]) + " |"
    rows = ["| " + " | ".join(r) + " |" for r in table[1:]]
    return [head, sep, *rows]


def _marker(slide: Slide) -> str:
    data = {"id": slide.key}
    if slide.image:
        data["img"] = slide.image
    if slide.template_name:
        data["template"] = slide.template_name
        if slide.title:
            data["h1"] = slide.title
        if slide.kicker:
            data["h2"] = slide.kicker
        body_md = "\n".join(_render_para(p) for p in slide.paras)
        if body_md:
            data["body"] = body_md
        if slide.vars:
            data["vars"] = slide.vars
    elif slide.layout_name and slide.layout_name not in SECTION_LAYOUTS:
        data["tpl"] = slide.layout_name
    return f"<!-- s2g {json.dumps(data, separators=(',', ':'))} -->"


# ---------------------------------------------------------------------------
# Push:  Slide -> batchUpdate
# ---------------------------------------------------------------------------

STYLE = {
    "bold": ({"bold": True}, "bold"),
    "italic": ({"italic": True}, "italic"),
    "code": ({"fontFamily": "Roboto Mono"}, "fontFamily"),
}


FILLABLE = {"TITLE", "CENTERED_TITLE", "SUBTITLE", "BODY"}


def _font_all(obj_id, rgb, bold=None, cell=None) -> dict:
    """Set the brand font + colour over all text in a shape or table cell."""
    style = {"fontFamily": BRAND_FONT,
             "foregroundColor": {"opaqueColor": {"rgbColor": rgb}}}
    fields = "fontFamily,foregroundColor"
    if bold is not None:
        style["bold"] = bold
        fields += ",bold"
    req = {"objectId": obj_id, "textRange": {"type": "ALL"},
           "style": style, "fields": fields}
    if cell is not None:
        req["cellLocation"] = {"rowIndex": cell[0], "columnIndex": cell[1]}
    return {"updateTextStyle": req}


def _kicker(tid) -> list[dict]:
    """Style a slide title as the deck's red, centered kicker label."""
    return [
        {"updateTextStyle": {"objectId": tid, "textRange": {"type": "ALL"},
            "style": {"fontFamily": BRAND_FONT, "bold": False,
                      "fontSize": {"magnitude": 18, "unit": "PT"},
                      "foregroundColor": {"opaqueColor": {"rgbColor": RED}}},
            "fields": "fontFamily,bold,fontSize,foregroundColor"}},
        {"updateParagraphStyle": {"objectId": tid, "textRange": {"type": "ALL"},
            "style": {"alignment": "CENTER"}, "fields": "alignment"}},
    ]


@dataclass
class Style:
    bg: dict                  # slide background
    headline_pt: int | None   # None -> no separate headline (kicker is the title)
    headline_rgb: dict
    body_align: str | None    # CENTER | START | None (no body region)
    top: float                # starting y (inches) of the kicker/headline block


# Built-in brand kit matching the Reliable Monitors deck (no in-deck templates).
STYLES = {
    "dark":     Style(DARK_BG, 72, PAPER, None, 2.0),      # dark title card
    "title":    Style(DARK_BG, 72, PAPER, None, 2.0),
    "appendix": Style(LIGHT_BG, 72, INK, None, 2.0),       # light title card
    "label":    Style(LIGHT_BG, 50, INK, "CENTER", 1.5),   # question + centered body
    "question": Style(LIGHT_BG, 50, INK, "CENTER", 1.5),
    "topic":    Style(LIGHT_BG, 40, INK, "START", 0.6),    # headline + left body
    "content":  Style(LIGHT_BG, None, INK, "START", 0.4),  # kicker-as-title + left body
}


def _est_lines(text: str, pt: int, width_in: float = 9.32) -> int:
    """Estimate wrapped line count for a headline (rough, font-metric free)."""
    chars_per_line = max(1, int(width_in * 72 / (pt * 0.52)))
    return max(1, math.ceil(len(text) / chars_per_line))


def _styled_requests(slide: Slide, style: Style, image_url, image_px) -> list[dict]:
    sid = slide.object_id
    reqs = [{"createSlide": {"objectId": sid,
                             "slideLayoutReference": {"predefinedLayout": "BLANK"}}},
            _bg(sid, style.bg)]
    if style.headline_pt is None:           # content: the kicker IS the title
        kicker_text, headline_text = slide.title, None
    else:
        kicker_text, headline_text = slide.kicker, slide.title
    head_h = 0.0
    if headline_text:
        head_h = _est_lines(headline_text, style.headline_pt) \
            * style.headline_pt * 1.25 / 72 + 0.1
    # Title cards (no body, no image) vertically centre the kicker+headline.
    if (style.body_align is None or not slide.paras) and not slide.image:
        block = (0.62 if kicker_text else 0) + head_h
        y = max(0.4, (5.63 - block) / 2)
    else:
        y = style.top
    if kicker_text:
        reqs += _text_box(sid, sid + "_k", (0.34, y, 9.32, 0.5),
                          kicker_text, 18, RED, False)
        y += 0.62
    if headline_text:
        reqs += _text_box(sid, sid + "_h", (0.34, y, 9.32, head_h),
                          headline_text, style.headline_pt, style.headline_rgb,
                          True)
        y += head_h + 0.15
    if style.body_align and slide.paras:
        bid = sid + "_b"
        reqs.append({"createShape": {"objectId": bid, "shapeType": "TEXT_BOX",
            "elementProperties": {"pageObjectId": sid,
                "size": {"width": {"magnitude": _emu(9.32), "unit": "EMU"},
                         "height": {"magnitude": _emu(max(5.2 - y, 1.0)),
                                    "unit": "EMU"}},
                "transform": {"scaleX": 1, "scaleY": 1, "translateX": _emu(0.34),
                              "translateY": _emu(y), "unit": "EMU"}}}})
        reqs += _body(bid, slide.paras, align=style.body_align)
    if slide.image and image_url:
        avail = _emu(max(5.4 - y, 1.5))
        w, h = _fit2(image_px, _emu(9.32), avail)
        reqs.append({"createImage": {
            "objectId": sid + "_img", "url": image_url,
            "elementProperties": {"pageObjectId": sid,
                "size": {"width": {"magnitude": w, "unit": "EMU"},
                         "height": {"magnitude": h, "unit": "EMU"}},
                "transform": {"scaleX": 1, "scaleY": 1, "unit": "EMU",
                              "translateX": (SLIDE_W - w) // 2,
                              "translateY": _emu(y)}}}})
    return reqs


def _fit2(px, max_w, max_h):
    if not px:
        return max_w, max_h
    w, h = px[0] * EMU_PER_PX, px[1] * EMU_PER_PX
    scale = min(max_w / w, max_h / h, 1.0)
    return int(w * scale), int(h * scale)


def _graph_requests(slide: Slide, image_url, image_px) -> list[dict]:
    """Full-bleed graph: a single image maximised to fill the page, no text.

    For `template: graph` / `full` slides — the figure is self-titled, so the
    slide carries no kicker, headline, or body. The image is scaled to fit the
    slide (aspect preserved) with a thin margin and centred both ways.
    """
    sid = slide.object_id
    reqs = [{"createSlide": {"objectId": sid,
                             "slideLayoutReference": {"predefinedLayout": "BLANK"}}},
            _bg(sid, LIGHT_BG)]
    if slide.image and image_url:
        margin = _emu(0.1)
        w, h = _fit2(image_px, SLIDE_W - 2 * margin, SLIDE_H - 2 * margin)
        reqs.append({"createImage": {
            "objectId": sid + "_img", "url": image_url,
            "elementProperties": {"pageObjectId": sid,
                "size": {"width": {"magnitude": w, "unit": "EMU"},
                         "height": {"magnitude": h, "unit": "EMU"}},
                "transform": {"scaleX": 1, "scaleY": 1, "unit": "EMU",
                              "translateX": (SLIDE_W - w) // 2,
                              "translateY": (SLIDE_H - h) // 2}}}})
    return reqs


def slide_requests(slide: Slide, image_url, image_px,
                   layouts=None, templates=None) -> list[dict]:
    tpl = (slide.template_name or "").lower()
    if tpl in ("graph", "full"):
        return _graph_requests(slide, image_url, image_px)
    if tpl in STYLES:
        return _styled_requests(slide, STYLES[tpl], image_url, image_px)
    if templates and tpl in templates:
        return _tagged_requests(slide, templates[tpl])
    name = (slide.layout_name or "").lower()
    if layouts and name in layouts and slide.layout_name not in SECTION_LAYOUTS:
        return _layout_requests(slide, layouts[name])
    tid = slide.object_id + "_t"
    if slide.layout == "section":
        reqs = _create(slide, "TITLE", [("CENTERED_TITLE", tid)])
        reqs += _insert(tid, slide.title)
        reqs += [_bg(slide.object_id, DARK_BG), _font_all(tid, PAPER, bold=True)]
    elif slide.layout == "content":
        bid = slide.object_id + "_b"
        reqs = _create(slide, "TITLE_AND_BODY", [("TITLE", tid), ("BODY", bid)])
        reqs += _insert(tid, slide.title) + _body(bid, slide.paras)
        reqs += [_bg(slide.object_id, LIGHT_BG)] + _kicker(tid)
    else:
        reqs = _create(slide, "TITLE_ONLY", [("TITLE", tid)])
        reqs += _insert(tid, slide.title)
        reqs += [_bg(slide.object_id, LIGHT_BG)] + _kicker(tid)
        if slide.layout == "image" and image_url:
            reqs.append(_image(slide, image_url, image_px))
        elif slide.layout == "table" and slide.table:
            reqs += _table(slide)
    return reqs


def _plain_body(paras: list[Para]) -> str:
    return "\n".join(p.text for p in paras)


def _tagged_requests(slide: Slide, template_id: str) -> list[dict]:
    """Duplicate a styled template slide and interpolate {{token}} text."""
    reqs = [{"duplicateObject": {"objectId": template_id,
                                 "objectIds": {template_id: slide.object_id}}}]
    tokens = {"h1": slide.title, "title": slide.title, "h2": slide.kicker,
              "body": _plain_body(slide.paras), **slide.vars}
    for tok, val in tokens.items():
        reqs.append({"replaceAllText": {
            "containsText": {"text": "{{" + tok + "}}", "matchCase": True},
            "replaceText": str(val), "pageObjectIds": [slide.object_id]}})
    return reqs


def _layout_requests(slide: Slide, lay: dict) -> list[dict]:
    """Fill a themed master layout's placeholders from the slide's structure."""
    ids, mappings = {}, []
    for t, idx in lay["ph"]:
        if t not in FILLABLE:
            continue
        oid = f"{slide.object_id}_{t}{idx}"
        ids[(t, idx)] = oid
        mappings.append({"layoutPlaceholder": {"type": t, "index": idx},
                         "objectId": oid})
    reqs = [{"createSlide": {
        "objectId": slide.object_id,
        "slideLayoutReference": {"layoutId": lay["id"]},
        "placeholderIdMappings": mappings,
    }}]
    title_key = ("TITLE", 0) if ("TITLE", 0) in ids else ("CENTERED_TITLE", 0)
    if title_key in ids:
        reqs += _insert(ids[title_key], slide.title)
    if ("BODY", 0) in ids:
        reqs += _body(ids[("BODY", 0)], slide.paras)
    return reqs


def _create(slide, layout, placeholders) -> list[dict]:
    mappings = [{"layoutPlaceholder": {"type": t, "index": 0}, "objectId": oid}
                for t, oid in placeholders]
    return [{"createSlide": {
        "objectId": slide.object_id,
        "slideLayoutReference": {"predefinedLayout": layout},
        "placeholderIdMappings": mappings,
    }}]


def _insert(obj_id, text) -> list[dict]:
    return [{"insertText": {"objectId": obj_id, "text": text}}] if text else []


def _body(bid: str, paras: list[Para], align: str = "START") -> list[dict]:
    lines = ["\t" * max(p.depth, 0) + p.text for p in paras]
    full = "\n".join(lines)
    if not full:
        return []
    reqs = [{"insertText": {"objectId": bid, "text": full}},
            _font_all(bid, BODY_INK)]  # base brand font; inline runs override below
    bullets, off = [], 0
    for line, p in zip(lines, paras):
        cbase = off + _u16("\t" * max(p.depth, 0))
        for r in p.runs:
            if r.style == "link" and r.link.startswith("#"):
                continue  # internal slide links: resolved in _apply_internal_links
            s = cbase + _u16(p.text[:r.start])
            e = cbase + _u16(p.text[:r.end])
            reqs.append(_style(bid, s, e, r))
        if p.depth >= 0:
            bullets.append((off, off + _u16(line), p.ordered))
        off += _u16(line) + 1
    total = _u16(full)
    bullets = [(s, min(e, total), o) for s, e, o in bullets if s < min(e, total)]
    reqs += _bullets(bid, bullets)
    reqs.append({"updateParagraphStyle": {"objectId": bid,
        "textRange": {"type": "ALL"}, "style": {"alignment": align},
        "fields": "alignment"}})
    return reqs


def _style(obj_id, start, end, run: Run) -> dict:
    rng = {"type": "FIXED_RANGE", "startIndex": start, "endIndex": end}
    if run.style == "link":
        return {"updateTextStyle": {"objectId": obj_id, "textRange": rng,
                                    "style": {"link": {"url": run.link}},
                                    "fields": "link"}}
    style, fields = STYLE[run.style]
    return {"updateTextStyle": {"objectId": obj_id, "textRange": rng,
                                "style": style, "fields": fields}}


def _bullets(bid, spans) -> list[dict]:
    out = []
    # Apply right-to-left: createParagraphBullets removes the leading tabs used
    # for nesting, shrinking the text, which would shift later groups' indices.
    for s, e, ordered in reversed(_merge(spans)):
        preset = "NUMBERED_DIGIT_ALPHA_ROMAN" if ordered \
            else "BULLET_DISC_CIRCLE_SQUARE"
        out.append({"createParagraphBullets": {
            "objectId": bid,
            "textRange": {"type": "FIXED_RANGE", "startIndex": s, "endIndex": e},
            "bulletPreset": preset,
        }})
    return out


def _merge(spans):
    merged = []
    for s, e, ordered in sorted(spans):
        if merged and ordered == merged[-1][2] and s <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], e, ordered)
        else:
            merged.append((s, e, ordered))
    return merged


def _image(slide, url, px) -> dict:
    w, h = _fit(px)
    return {"createImage": {
        "objectId": slide.object_id + "_img", "url": url,
        "elementProperties": {
            "pageObjectId": slide.object_id,
            "size": {"width": {"magnitude": w, "unit": "EMU"},
                     "height": {"magnitude": h, "unit": "EMU"}},
            "transform": {"scaleX": 1, "scaleY": 1, "unit": "EMU",
                          "translateX": (SLIDE_W - w) // 2, "translateY": BODY_Y},
        },
    }}


def _fit(px):
    if not px:
        return BODY_W, BODY_H
    w, h = px[0] * EMU_PER_PX, px[1] * EMU_PER_PX
    scale = min(BODY_W / w, BODY_H / h, 1.0)
    return int(w * scale), int(h * scale)


def _table(slide) -> list[dict]:
    rows, cols = len(slide.table), len(slide.table[0])
    tid = slide.object_id + "_tbl"
    reqs = [{"createTable": {
        "objectId": tid,
        "elementProperties": {
            "pageObjectId": slide.object_id,
            "transform": {"scaleX": 1, "scaleY": 1, "unit": "EMU",
                          "translateX": BODY_X, "translateY": BODY_Y},
        },
        "rows": rows, "columns": cols,
    }}]
    for r, row in enumerate(slide.table):
        for c, cell in enumerate(row):
            if cell:
                reqs.append({"insertText": {
                    "objectId": tid, "text": cell,
                    "cellLocation": {"rowIndex": r, "columnIndex": c}}})
                reqs.append(_font_all(tid, INK if r == 0 else BODY_INK,
                                      bold=(r == 0), cell=(r, c)))
    return reqs


# ---------------------------------------------------------------------------
# Push:  diff + execute
# ---------------------------------------------------------------------------


def managed_slides(slides_api, deck) -> dict[str, tuple[str, str]]:
    pres = slides_api.presentations().get(presentationId=deck).execute()
    out = {}
    for s in pres.get("slides", []):
        if MANAGED_RE.match(s["objectId"]):
            _, kh, ch = s["objectId"].split("_")
            out[kh] = (s["objectId"], ch)
    return out


def _template_index(slides_api, deck) -> dict[str, str]:
    """name(lower) -> objectId for slides tagged `<!-- s2g:template NAME -->`."""
    pres = slides_api.presentations().get(presentationId=deck).execute()
    out = {}
    for s in pres.get("slides", []):
        m = TEMPLATE_TAG_RE.search(_read_notes(s))
        if m:
            out[m.group("name").lower()] = s["objectId"]
    return out


def _layout_map(slides_api, deck) -> dict[str, dict]:
    """displayName(lower) -> {id, ph:[(type,index)]} for the deck's master layouts."""
    pres = slides_api.presentations().get(presentationId=deck).execute()
    out = {}
    for lay in pres.get("layouts", []):
        name = lay.get("layoutProperties", {}).get("displayName")
        if not name:
            continue
        ph = [(el["shape"]["placeholder"].get("type"),
               el["shape"]["placeholder"].get("index", 0))
              for el in lay.get("pageElements", [])
              if el.get("shape", {}).get("placeholder")]
        out[name.lower()] = {"id": lay["objectId"], "ph": ph}
    return out


def plan_sync(source: list[Slide], managed: dict, prune: bool):
    creates, deletes, skips = [], [], []
    for s in source:
        if s.key_hash in managed:
            old_id, old_ch = managed[s.key_hash]
            (skips if old_ch == s.content_hash else creates).append(s)
            if old_ch != s.content_hash:
                deletes.append(old_id)
        else:
            creates.append(s)
    keys = {s.key_hash for s in source}
    pruned = [oid for kh, (oid, _) in managed.items() if kh not in keys and prune]
    return creates, deletes, skips, pruned


def push(slides_api, drive, deck, source, anchor, prune, base_dir=Path(".")) -> dict:
    managed = managed_slides(slides_api, deck)
    layouts = _layout_map(slides_api, deck)
    templates = _template_index(slides_api, deck)
    creates, deletes, skips, pruned = plan_sync(source, managed, prune)
    reqs = [{"deleteObject": {"objectId": oid}} for oid in deletes + pruned]
    create_set = set(id(s) for s in creates)
    for s in source:
        if id(s) not in create_set:
            continue
        url, px = _resolve_image(drive, s, base_dir)
        reqs += slide_requests(s, url, px, layouts, templates)
    if reqs:
        _batch(slides_api, deck, reqs)
    _apply_notes(slides_api, deck, creates)
    _reorder(slides_api, deck, source, anchor)
    _apply_internal_links(slides_api, deck, source)
    return {"create": len(creates), "skip": len(skips),
            "replace": len(deletes), "prune": len(pruned)}


# Templates with no body region, so they cannot host an internal-link run.
NOBODY_TEMPLATES = {"dark", "title", "appendix", "graph", "full"}


def _apply_internal_links(slides_api, deck, source) -> None:
    """Resolve `[text](#key)` body links to native Slides slide links.

    Runs over ALL source slides on every push (not only created ones) so a link
    stays valid even when its *target* slide's content — hence objectId —
    changes while the linking slide is unchanged. Title links are dropped at
    parse time, so only body (`_b`) runs carry internal links.
    """
    key_to_oid = {s.key: s.object_id for s in source}
    reqs = []
    for s in source:
        if (s.template_name or "").lower() in NOBODY_TEMPLATES:
            _warn_orphan_links(s)
            continue
        bid = s.object_id + "_b"
        off = 0
        for p in s.paras:
            for r in p.runs:
                if r.style == "link" and r.link.startswith("#"):
                    oid = key_to_oid.get(r.link[1:])
                    if not oid:
                        logger.warning(f"internal link {r.link} on '{s.key}' "
                                       "has no matching slide id")
                        continue
                    reqs.append({"updateTextStyle": {"objectId": bid,
                        "textRange": {"type": "FIXED_RANGE",
                                      "startIndex": off + _u16(p.text[:r.start]),
                                      "endIndex": off + _u16(p.text[:r.end])},
                        "style": {"link": {"pageObjectId": oid}},
                        "fields": "link"}})
            off += _u16(p.text) + 1
    if reqs:
        _batch(slides_api, deck, reqs)


def _warn_orphan_links(slide: Slide) -> None:
    if any(r.style == "link" and r.link.startswith("#")
           for p in slide.paras for r in p.runs):
        logger.warning(f"internal link on '{slide.key}' ignored: template "
                       f"'{slide.template_name}' has no body region")


def _resolve_image(drive, slide: Slide, base_dir=Path(".")):
    if slide.layout != "image" or not slide.image:
        return None, None
    p = Path(slide.image)
    if not p.is_absolute():
        p = base_dir / p
    if not p.exists():
        logger.warning(f"image not found, graphic skipped: {p}")
        return None, None
    return upload_image(drive, p), png_size(p)


def _batch(slides_api, deck, requests):
    slides_api.presentations().batchUpdate(
        presentationId=deck, body={"requests": requests}).execute()


def _apply_notes(slides_api, deck, creates):
    want = {s.object_id: (s.notes + "\n\n\n" + _marker(s)).strip()
            for s in creates}
    if not want:
        return
    pres = slides_api.presentations().get(presentationId=deck).execute()
    reqs = []
    for s in pres.get("slides", []):
        if s["objectId"] not in want:
            continue
        nid = _notes_shape_id(s)
        if not nid:
            continue
        if _read_notes(s):  # clear any notes inherited from a duplicated template
            reqs.append({"deleteText": {"objectId": nid,
                                        "textRange": {"type": "ALL"}}})
        reqs.append({"insertText": {"objectId": nid, "text": want[s["objectId"]]}})
    if reqs:
        _batch(slides_api, deck, reqs)


def _notes_shape_id(slide):
    notes_page = slide.get("slideProperties", {}).get("notesPage", {})
    nid = notes_page.get("notesProperties", {}).get("speakerNotesObjectId")
    if nid:
        return nid
    for el in notes_page.get("pageElements", []):
        if el.get("shape", {}).get("placeholder", {}).get("type") == "BODY":
            return el["objectId"]
    return None


def _reorder(slides_api, deck, source, anchor):
    pres = slides_api.presentations().get(presentationId=deck).execute()
    order = [s["objectId"] for s in pres.get("slides", [])]
    want = [s.object_id for s in source if s.object_id in order]
    if not want:
        return
    # Managed slides sit after any hand-built slides but BEFORE trailing
    # template (s2gtpl_) slides, which stay parked at the end.
    tpl_at = next((i for i, o in enumerate(order) if o.startswith("s2gtpl_")),
                  len(order))
    if anchor and anchor in order:
        base = order.index(anchor) + 1
    else:
        base = sum(1 for o in order[:tpl_at] if not MANAGED_RE.match(o))
    # updateSlidesPosition can't reorder slides relative to each other, so move
    # one at a time into position (sequential requests act like insertion sort).
    reqs = [{"updateSlidesPosition": {"slideObjectIds": [oid],
                                      "insertionIndex": base + i}}
            for i, oid in enumerate(want)]
    _batch(slides_api, deck, reqs)


# ---------------------------------------------------------------------------
# Image hosting
# ---------------------------------------------------------------------------


def png_size(path: Path):
    head = path.read_bytes()[:24]
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")
    return None


def upload_image(drive, path: Path) -> str:
    cache = json.loads(IMAGE_CACHE.read_text()) if IMAGE_CACHE.exists() else {}
    digest = hashlib.sha1(path.read_bytes()).hexdigest()
    if digest in cache:
        return cache[digest]
    media = MediaFileUpload(str(path), mimetype="image/png")
    f = drive.files().create(body={"name": path.name}, media_body=media,
                             fields="id").execute()
    drive.permissions().create(
        fileId=f["id"], body={"type": "anyone", "role": "reader"}).execute()
    url = f"https://drive.google.com/uc?export=download&id={f['id']}"
    cache[digest] = url
    IMAGE_CACHE.parent.mkdir(parents=True, exist_ok=True)
    IMAGE_CACHE.write_text(json.dumps(cache, indent=2))
    return url


# ---------------------------------------------------------------------------
# Pull:  native objects -> Slide
# ---------------------------------------------------------------------------


def pull_slides(slides_api, deck, managed_only=True) -> list[Slide]:
    pres = slides_api.presentations().get(presentationId=deck).execute()
    out = []
    for s in pres.get("slides", []):
        if managed_only and not MANAGED_RE.match(s["objectId"]):
            continue
        out.append(_finalize(_slide_from_native(s)))
    return out


def _slide_from_native(s) -> Slide:
    notes_raw = _read_notes(s)
    marker = _read_marker(notes_raw)
    notes = MARKER_RE.sub("", notes_raw).strip()
    if marker.get("template"):
        return _slide_from_marker(marker, notes)
    title, paras, image_el, table = "", [], None, None
    for el in s.get("pageElements", []):
        kind, value = _classify(el)
        if kind == "title":
            title = value
        elif kind == "body":
            paras = value
        elif kind == "image":
            image_el = value
        elif kind == "table":
            table = value
    image = marker.get("img") if image_el is not None else None
    layout = _infer_layout(paras, image, table)
    key = marker.get("id") or _slug(title) or s["objectId"]
    slide = Slide(key, layout, title, paras, image, table, notes)
    slide.layout_name = marker.get("tpl") or ("section" if layout == "section"
                                              else None)
    return slide


def _slide_from_marker(marker: dict, notes: str) -> Slide:
    """Reconstruct a tagged-template slide from its notes marker (source of truth)."""
    _headings, paras, _, _, _ = parse_body(marker.get("body", ""))
    img = marker.get("img")
    slide = Slide(marker["id"], "image" if img else "content",
                  marker.get("h1", ""), paras, image=img, notes=notes)
    slide.kicker = marker.get("h2", "")
    slide.template_name = marker["template"]
    slide.vars = marker.get("vars", {})
    return slide


def _classify(el):
    if "table" in el:
        return "table", _table_from_native(el["table"])
    if "image" in el:
        return "image", el
    shape = el.get("shape", {})
    ph = shape.get("placeholder", {}).get("type")
    text = _paras_from_shape(shape)
    if ph in ("TITLE", "CENTERED_TITLE"):
        return "title", _flatten(text)
    if text:
        return "body", text
    return "none", None


def _infer_layout(paras, image, table):
    if image:
        return "image"
    if table:
        return "table"
    if not paras:
        return "section"
    return "content"


def _flatten(paras: list[Para]) -> str:
    return " ".join(p.text for p in paras)


def _paras_from_shape(shape) -> list[Para]:
    elements = shape.get("text", {}).get("textElements", [])
    paras, cur, depth, base = [], None, -1, 0
    for el in elements:
        if "paragraphMarker" in el:
            if cur is not None:
                paras.append(_finish_para(cur, depth))
            bullet = el["paragraphMarker"].get("bullet")
            depth = bullet.get("nestingLevel", 0) if bullet is not None else -1
            cur, base = {"text": "", "runs": []}, 0
        elif "textRun" in el and cur is not None:
            base = _consume_run(el["textRun"], cur, base)
    if cur is not None:
        paras.append(_finish_para(cur, depth))
    while paras and not paras[0].text and not paras[0].runs:
        paras.pop(0)
    while paras and not paras[-1].text and not paras[-1].runs:
        paras.pop()
    return paras  # keep internal blank paragraphs for spacing


def _consume_run(tr, cur, base) -> int:
    content = tr.get("content", "").replace("\n", "")
    style = tr.get("style", {})
    name = _style_name(style)
    start = base
    cur["text"] += content
    if name:
        link = style.get("link", {}).get("url") if name == "link" else None
        cur["runs"].append(Run(start, start + len(content), name, link))
    return start + len(content)


def _style_name(style) -> str | None:
    if style.get("link", {}).get("url"):
        return "link"
    if "Mono" in style.get("fontFamily", ""):
        return "code"
    if style.get("bold"):
        return "bold"
    if style.get("italic"):
        return "italic"
    return None


def _finish_para(cur, depth) -> Para:
    text = cur["text"].lstrip("\t")
    shift = len(cur["text"]) - len(text)
    runs = [Run(r.start - shift, r.end - shift, r.style, r.link) for r in cur["runs"]]
    return Para(text, [r for r in runs if r.end > r.start], depth)


def _table_from_native(table) -> list[list[str]]:
    rows = []
    for row in table.get("tableRows", []):
        cells = []
        for cell in row.get("tableCells", []):
            cells.append(_flatten(_paras_from_shape(cell)))
        rows.append(cells)
    return rows


def _read_notes(s) -> str:
    notes_page = s.get("slideProperties", {}).get("notesPage", {})
    nid = notes_page.get("notesProperties", {}).get("speakerNotesObjectId")
    for el in notes_page.get("pageElements", []):
        if el.get("objectId") == nid or \
                el.get("shape", {}).get("placeholder", {}).get("type") == "BODY":
            return _flatten(_paras_from_shape(el.get("shape", {})))
    return ""


def _read_marker(notes: str) -> dict:
    m = MARKER_RE.search(notes)
    return json.loads(m.group("json")) if m else {}


def write_slidev(slides: list[Slide], path: Path):
    fm = ["theme: seriph"]
    if path.exists():
        deck = frontmatter.loads(path.read_text()).metadata.get("deck")
        if deck:
            fm.append(f"deck: {deck}")
    body = "\n---\n".join(to_slidev(s) for s in slides)
    path.write_text("---\n" + "\n".join(fm) + "\n---\n\n" + body)


# ---------------------------------------------------------------------------
# Branded templates (match the Reliable Monitors deck)
# ---------------------------------------------------------------------------


def _emu(inches: float) -> int:
    return int(inches * EMU_PER_IN)


def _text_box(slide_id, box_id, box, text, size, rgb, bold, valign=None) -> list[dict]:
    x, y, w, h = box
    reqs = [
        {"createShape": {"objectId": box_id, "shapeType": "TEXT_BOX",
            "elementProperties": {"pageObjectId": slide_id,
                "size": {"width": {"magnitude": _emu(w), "unit": "EMU"},
                         "height": {"magnitude": _emu(h), "unit": "EMU"}},
                "transform": {"scaleX": 1, "scaleY": 1, "translateX": _emu(x),
                              "translateY": _emu(y), "unit": "EMU"}}}},
        {"insertText": {"objectId": box_id, "text": text}},
        {"updateTextStyle": {"objectId": box_id, "textRange": {"type": "ALL"},
            "style": {"fontFamily": BRAND_FONT, "bold": bold,
                      "fontSize": {"magnitude": size, "unit": "PT"},
                      "foregroundColor": {"opaqueColor": {"rgbColor": rgb}}},
            "fields": "fontFamily,bold,fontSize,foregroundColor"}},
        {"updateParagraphStyle": {"objectId": box_id, "textRange": {"type": "ALL"},
            "style": {"alignment": "CENTER"}, "fields": "alignment"}},
    ]
    if valign:
        reqs.append({"updateShapeProperties": {"objectId": box_id,
            "shapeProperties": {"contentAlignment": valign},
            "fields": "contentAlignment"}})
    return reqs


def _bg(slide_id, rgb) -> dict:
    return {"updatePageProperties": {"objectId": slide_id,
        "pageProperties": {"pageBackgroundFill": {"solidFill": {
            "color": {"rgbColor": rgb}}}},
        "fields": "pageBackgroundFill.solidFill.color"}}


def _branded_template(name, bg, headline_rgb, body_rgb, hsize, with_body) -> list[dict]:
    """Centered kicker + headline (+ body) template, matching the deck's style."""
    sid = f"s2gtpl_{name}"
    reqs = [{"createSlide": {"objectId": sid,
                             "slideLayoutReference": {"predefinedLayout": "BLANK"}}},
            _bg(sid, bg)]
    reqs += _text_box(sid, sid + "_k", (0.34, 1.6, 9.32, 0.5),
                      "{{h2}}", 17, RED, False)
    reqs += _text_box(sid, sid + "_h", (0.34, 2.05, 9.32, 1.7),
                      "{{h1}}", hsize, headline_rgb, True, valign="MIDDLE")
    if with_body:
        reqs += _text_box(sid, sid + "_b", (0.34, 3.85, 9.32, 1.4),
                          "{{body}}", 24, body_rgb, False)
    return reqs


# (name, background, headline colour, body colour, headline pt, has-body)
TEMPLATE_SPECS = [
    ("label", LIGHT_BG, INK, BODY_INK, 50, True),
    ("dark", DARK_BG, PAPER, PAPER, 72, False),
]


def make_templates(slides_api, deck):
    reqs = []
    for spec in TEMPLATE_SPECS:
        reqs += _branded_template(*spec)
    _batch(slides_api, deck, reqs)
    names = [s[0] for s in TEMPLATE_SPECS]
    pres = slides_api.presentations().get(presentationId=deck).execute()
    tag = []
    for s in pres.get("slides", []):
        if s["objectId"] in {f"s2gtpl_{n}" for n in names}:
            nid = _notes_shape_id(s)
            if nid:
                tag.append({"insertText": {"objectId": nid,
                            "text": f"<!-- s2g:template {s['objectId'][7:]} -->"}})
    if tag:
        _batch(slides_api, deck, tag)
    _hide_templates(slides_api, deck, [f"s2gtpl_{n}" for n in names])
    return names


def _hide_templates(slides_api, deck, ids):
    """Skip template slides in the slideshow (best effort)."""
    pres = slides_api.presentations().get(
        presentationId=deck, fields="slides.objectId").execute()
    present = {s["objectId"] for s in pres.get("slides", [])} & set(ids)
    if not present:
        return
    try:
        _batch(slides_api, deck, [{"updateSlideProperties": {
            "objectId": i, "slideProperties": {"isSkipped": True},
            "fields": "isSkipped"}} for i in present])
    except Exception as e:  # noqa: BLE001 - API may not expose isSkipped
        logger.warning(f"could not mark templates skipped: {e}")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

SAMPLE = """---
theme: seriph
---

---
layout: section
id: intro
---

# Round-trip check

<!-- opening remarks for the section -->

---
id: findings
---

## Key findings

- First **bold** point
  - nested with `code`
  - nested with *italic*
- Second point with a [link](https://example.com)

<!-- talk through each finding -->

---
id: data
---

## The numbers

| Metric | Value |
| --- | --- |
| AUROC | 0.93 |
| Gap | small |

---
template: label
id: ask
---

## QUESTION

# What should we prioritise?

- summarisation first
- collusion is characterise-only

<!-- the ask -->

---
template: dark
id: titlecard
---

## MEETING

# 2026/06/01
"""


def new_deck(slides_api, title: str) -> str:
    """Create a deck and remove the default blank slide Google inserts."""
    deck = slides_api.presentations().create(
        body={"title": title}).execute()["presentationId"]
    pres = slides_api.presentations().get(presentationId=deck).execute()
    reqs = [{"deleteObject": {"objectId": s["objectId"]}}
            for s in pres.get("slides", [])]
    if reqs:
        _batch(slides_api, deck, reqs)
    return deck


DECK_ID_RE = re.compile(r"/presentation/d/(?P<id>[A-Za-z0-9_-]+)")


def deck_from_source(path: Path) -> str | None:
    """Read the target deck id from the file's top-level `deck:` frontmatter."""
    val = frontmatter.loads(path.read_text()).metadata.get("deck")
    if not val:
        return None
    m = DECK_ID_RE.search(str(val))
    return m.group("id") if m else str(val)


def cmd_push(args):
    source = load_slides(args.source)
    logger.info(f"parsed {len(source)} slides from {args.source}")
    slides_api, drive = get_services(args.account)
    deck = args.deck or deck_from_source(args.source)
    if args.new:
        deck = new_deck(slides_api, args.new)
        logger.info(f"created https://docs.google.com/presentation/d/{deck}/edit")
    if not deck:
        sys.exit("no target deck: pass --deck/--new or add `deck:` frontmatter")
    stats = push(slides_api, drive, deck, source, args.anchor, args.prune,
                 base_dir=args.source.parent)
    logger.success(f"{stats} -> https://docs.google.com/presentation/d/{deck}/edit")


def cmd_pull(args):
    slides_api, _ = get_services(args.account)
    slides = pull_slides(slides_api, args.deck, managed_only=not args.all)
    write_slidev(slides, args.out)
    logger.success(f"pulled {len(slides)} slides -> {args.out}")


def cmd_make_templates(args):
    slides_api, _ = get_services(args.account)
    names = make_templates(slides_api, args.deck)
    logger.success(f"created templates {names} in "
                   f"https://docs.google.com/presentation/d/{args.deck}/edit")


def cmd_layouts(args):
    slides_api, _ = get_services(args.account)
    pres = slides_api.presentations().get(presentationId=args.deck).execute()
    for lay in pres.get("layouts", []):
        name = lay.get("layoutProperties", {}).get("displayName", "?")
        phs = []
        for el in lay.get("pageElements", []):
            ph = el.get("shape", {}).get("placeholder")
            if ph:
                phs.append(f"{ph.get('type')}[{ph.get('index', 0)}]")
        logger.info(f"{name:<24} {', '.join(phs) or '(no placeholders)'}")


def _loop_hop(slides_api, drive, title, slides):
    """One md->slides hop: build a deck, push, pull back."""
    deck = new_deck(slides_api, title)
    push(slides_api, drive, deck, slides, anchor=None, prune=False)
    return deck, pull_slides(slides_api, deck)


def cmd_roundtrip(args):
    slides_api, drive = get_services(args.account)
    src = build_slides(split_slides(SAMPLE))
    # md -> slides -> md -> slides
    deck_a, got_a = _loop_hop(slides_api, drive, "slidesync roundtrip A", src)
    deck_b, got_b = _loop_hop(slides_api, drive, "slidesync roundtrip B", got_a)
    logger.info(f"hop A https://docs.google.com/presentation/d/{deck_a}/edit")
    logger.info(f"hop B https://docs.google.com/presentation/d/{deck_b}/edit")
    ok = _compare(src, got_a) and _compare(got_a, got_b)
    if not args.keep:
        drive.files().delete(fileId=deck_a).execute()
        drive.files().delete(fileId=deck_b).execute()
        logger.info("scratch decks deleted")
    logger.log("SUCCESS" if ok else "ERROR",
               "loop stable" if ok else "loop DIVERGED")
    sys.exit(0 if ok else 1)


def _compare(src: list[Slide], got: list[Slide]) -> bool:
    if len(src) != len(got):
        logger.error(f"slide count {len(src)} != {len(got)}")
        return False
    ok = True
    for a, b in zip(src, got):
        if a.semantic() == b.semantic():
            logger.success(f"  [match] {a.key}")
            continue
        ok = False
        logger.error(f"  [DIFF]  {a.key}")
        for fa, fb, name in zip(a.semantic(), b.semantic(),
                                ["key", "layout_name", "template_name", "vars",
                                 "layout", "title", "kicker", "paras", "table",
                                 "image", "notes"]):
            if fa != fb:
                logger.error(f"    {name}: {fa!r} != {fb!r}")
    logger.log("SUCCESS" if ok else "ERROR",
               "round-trip PASS" if ok else "round-trip FAIL")
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--account", default=DEFAULT_ACCOUNT)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("push")
    p.add_argument("source", type=Path)
    p.add_argument("--deck")
    p.add_argument("--new")
    p.add_argument("--anchor")
    p.add_argument("--prune", action="store_true")
    p.set_defaults(func=cmd_push)

    p = sub.add_parser("pull")
    p.add_argument("deck")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--all", action="store_true", help="export non-managed slides too")
    p.set_defaults(func=cmd_pull)

    p = sub.add_parser("roundtrip")
    p.add_argument("--keep", action="store_true", help="keep the scratch deck")
    p.set_defaults(func=cmd_roundtrip)

    p = sub.add_parser("layouts", help="list a deck's master layouts + placeholders")
    p.add_argument("deck")
    p.set_defaults(func=cmd_layouts)

    p = sub.add_parser("make-templates",
                       help="add branded tagged template slides to a deck")
    p.add_argument("deck")
    p.set_defaults(func=cmd_make_templates)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
