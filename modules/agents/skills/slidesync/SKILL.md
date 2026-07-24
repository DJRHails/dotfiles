---
name: slidesync
description: Bidirectional sync between a Slidev markdown deck and Google Slides as native, editable objects (not images). Push markdown -> Slides, pull Slides -> markdown, and round-trip. Use when the user wants to author/version a Google Slides deck from markdown, replicate a deck's styling, or keep a .slidev.md in sync with a presentation. Auth is borrowed from the `gog` CLI (no separate OAuth setup). Requires the `gog` CLI installed and authenticated on the host (macOS or Linux) — slidesync reads gog's stored credentials from `~/.config/gogcli/` (Linux/XDG) or `~/Library/Application Support/gogcli/` (macOS); skip only where gog is not set up.
version: 1.1.0
metadata:
  hermes:
    tags: [Slides, GoogleSlides, Slidev, Markdown, Presentations, gog]
    related_skills: [gog]
---

# slidesync

Sync a Slidev markdown deck to/from Google Slides, building **native** Slides
objects (title/body/bullets/tables/positioned images, brand-styled text boxes) —
so the result stays editable, not a flat image. `pull` reconstructs the markdown
from those native objects; `roundtrip` proves the loop is stable.

Packaged at [github.com/DJRHails/slidesync](https://github.com/DJRHails/slidesync)
(PyPI: [`slidesync`](https://pypi.org/project/slidesync/)). Run with
**`uvx slidesync`** — no install needed.

## Auth (no setup)

Borrowed from `gog`: OAuth client id/secret resolved cross-platform from
`~/.config/gogcli/credentials.json` (Linux/XDG), falling back to
`~/Library/Application Support/gogcli/credentials.json` (macOS) — and the
keyring-password file at either location — mirroring gog's own resolution.
Refresh token via `gog auth tokens export`. The stored token already carries
`slides`+`drive` scopes. Requires the **Slides API enabled** on the gog Cloud
project.
The account defaults to gog's default account (override with `--account` or
`$SLIDESYNC_ACCOUNT`).

## Commands

| Command | Purpose |
|---------|---------|
| `slidesync push <file.slidev.md>... [--deck ID] [--new "Title"] [--anchor SLIDE] [--prune] [--force]` | md -> Slides (rejected if it would discard live Slides edits; `--force` overrides) |
| `slidesync pull <deckId> --out <file.md> [--all]` | Slides -> md (`--all` includes non-managed slides) |
| `slidesync sync <file.slidev.md>... [--deck ID] [--prune]` | reconcile with the live deck: capture comment threads as `<!-- @Author: ... -->`, write live edits back into the markdown, push local changes; conflicts print three-way diffs and exit 1 |
| `slidesync comments <deckId>` | list comment threads as JSON (page anchor, author, content, replies) |
| `slidesync roundtrip [--keep]` | self-test: push a sample, pull, assert identical |
| `slidesync layouts <deckId>` | list a deck's theme layouts + placeholders |
| `slidesync make-templates <deckId>` | inject legacy in-deck `{{token}}` template slides |

`push` resolves the target deck from (in order) `--deck`, `--new`, or a
top-level `deck:` frontmatter key (URL or bare id). Relative image paths resolve
against each slide's own source file. **Multi-file decks** (>=0.5): `push`/`sync`
accept several files (deck order = argument order, e.g. newest meeting first);
slide ids namespace as `<file-stem>-<id>` and intra-file `[text](#id)` links are
rewritten to the namespaced target. `sync` routes captured comments and live-edit
write-backs into the right source file.

```bash
uvx slidesync push deck.slidev.md          # targets `deck:` frontmatter
uvx slidesync push deck.slidev.md --new "Talk"
uvx slidesync pull <id> --out deck.slidev.md
uvx slidesync roundtrip
```

## Idempotent sync (upsert)

Each managed slide is created with `objectId = s2g_<keyHash>_<contentHash>`.
`keyHash` = per-slide `id:` frontmatter, else title slug, else index (survives
edits/reorders); `contentHash` is over a canonical render, so push->pull->push is
a no-op. Diff per run: identical hash -> skip; same key, new content -> replace;
new key -> create. Removed slides are **kept** unless `--prune`. **Only `s2g_`
slides are ever touched** — hand-authored slides are invisible to the sync. A
hidden `<!-- s2g {...} -->` marker in speaker notes carries the human id, image
path, template vars — and, for template slides, the authored body markdown
(base64) — so `pull` recovers the source verbatim (3 blank lines below the
real note).

## Markdown dialect

Top-level frontmatter: `theme:`, `deck:`. Slides separated by `---`; each slide
may have its own frontmatter (`id:`, `template:`, `layout:`, `hidden:`).

- `# h1` = headline, `## h2` above an h1 = kicker; a lone `##` is the title.
- `hidden: true` (or `hide: true`) marks a slide **skipped** in the deck — still
  a native, editable slide, just hidden in present mode (Slides API `isSkipped`),
  the analogue of Slidev's `hidden`. Part of the content hash (toggling re-pushes)
  and round-trips: `pull` reads the live skipped state back to `hidden: true`.
  Needs slidesync ≥0.9.0.
- Bullets `-`/`*`; ordered `1.` (nest with 2-space indent). Inline
  `**bold**` / `*italic*` / `` `code` `` / `[link](url)` (rendered brand-red +
  underlined). GFM tables. `![alt](path)`
  images (uploaded to Drive; `alt` becomes the image's accessibility
  description via `updatePageElementAltText`, round-tripped on pull).
  **Linked images** `[![alt](img)](href)` (≥0.11.2, the deck-variant crop →
  full-figure convention): parse as the image; an absolute http(s) `href`
  lands on the live element as its link, a relative repo path round-trips in
  the source but emits no live link. Blank
  lines preserved as spacing. `<!-- notes -->`
  become speaker notes — and (v0.2+) round-trip as **comments, in place**: on
  template slides `pull` re-emits each comment where it was written, not as one
  merged trailing blob; speaker notes edited live in Slides come back as one
  extra trailing comment. `<v-clicks>`/`<div>` are stripped.
- **Internal links:** `[text](#slide-id)` becomes a native Slides link that jumps
  to the slide whose `id:` (or title slug) is `slide-id`. Resolved against the
  whole push set and re-applied on every push, so links survive a target's
  content change. Only body links work (title links are dropped); a target on a
  no-body template (`dark`/`title`/`appendix`/`graph`) is warned and skipped.

### Built-in brand kit (IBM Plex; red #C0392B kicker)

Select per slide via `template:` — native styled boxes, no in-deck templates:

| `template:` | look |
|-------------|------|
| `dark` / `title` | dark #1E2024 bg, kicker + big white headline (centred); body lines render as a small dimmed **byline** beneath (e.g. `Project · Presenter`) |
| `appendix` | light #FAFAFA bg, kicker + big ink headline; body lines render as a small byline |
| `question` / `label` | kicker + headline + **centred** body |
| `topic` | kicker + headline + **left** body (and/or image) |
| `content` | red kicker-as-title + left body |
| `graph` / `full` | **text-free** apart from one optional link line: a single image scaled to fill the page (aspect preserved, centred, thin margin). A single link-only paragraph (`[a →](url) · [b →](url)`, ≥0.13.0) renders as an 11pt right-aligned bottom footer — wide images keep full size (footer sits in the free strip), taller ones shrink just enough; no links ⇒ no footer space. Any other title/body content is a slot ERROR (see validation below) |
| `prompt` / `code` | red kicker title + full body in **11pt Roboto Mono** filling the slide — for verbatim system prompts / code; one source line per paragraph, wraps naturally |

Slides with no `template:` fall back to a generative path (section /
TITLE_AND_BODY / table / image) that also brands bg + IBM Plex.

## Custom slides (diagrams) — pull-authoritative

For hand-drawn diagrams, give a slide a fenced ```` ```gslides ```` block holding
the **literal Slides API requests** (a JSON list, or `{"requests": [...]}`). Use
`__PAGE__` for the slide page id (element ids embedding it stay unique):

````markdown
---
id: my-diagram
---
```gslides
{"requests": [
  {"createShape": {"objectId": "__PAGE___box", "shapeType": "ROUND_RECTANGLE",
    "elementProperties": {"pageObjectId": "__PAGE__", "size": {...}, "transform": {...}}}},
  {"insertText": {"objectId": "__PAGE___box", "text": "Summariser"}}
]}
```
````

Sync is **pull-authoritative / push-if-missing**: the Google Slides copy is the
source of truth. `push` **creates** the slide from the block only when it is
**missing**; if it already exists it is **never overwritten** (even with
`--force`) — so you draw/edit natively in Slides and it survives every push.
`pull` **captures** the live drawing back into the ```` ```gslides ```` block as
requests, so `pull -> push -> pull` is a faithful fixed point (object id is keyed
on `id:` only, so native edits never orphan it).

Captured fidelity covers shapes (fill/outline/content-alignment), per-run +
per-paragraph **text** styling, **lines** (weight/dash/arrows), and images.
Inherent limits (the API forbids setting them, so they inherit defaults on a
*recreate-from-missing* only — the live slide is never degraded): `shadow` and
`autofit` are read-only; element **connections** are dropped; image `contentUrl`s
expire, so a long-after recreate may lose the image.

## Overlays — raw requests on top of a templated slide (≥0.11.0)

A ```` ```gslides-overlay ```` block rides on a **normal templated/generative
slide** (unlike ```` ```gslides ````, which replaces the whole slide): its
literal Slides API requests are replayed **after** the slide's own render on
every push, `__PAGE__` substituted with the slide page id. Use it for the
annotation layer a template can't express — label text boxes on a text-free
`graph` figure, arrows, callouts. Opposite authority to custom slides: the
**markdown is the source of truth** — the block folds into the content hash
(edits re-push), round-trips through the notes marker on `pull`, and a
content-changing push recreates the drawn elements; native edits to them in
Slides are NOT captured back. Drift/clobber checks count the overlay's
`insertText` lines as visible text (never its raw JSON), so an overlaid slide
reads as clean. Prefix element ids with `__PAGE__` to stay unique across
re-pushes. To seed a block from boxes already drawn live, capture them with
`slidesync._sync._elements_to_requests` (emits `__PAGE__`-relative requests).
For a text note under a `template: equation` maths block, prefer LaTeX inside
the `$$` (`\underset{\uparrow\ \text{note}}{...}` — mathtext has no
`\underbrace`) over an overlay box.

## Template-slot validation (≥0.12.0)

`push`/`sync` exit 1 up front when a slide carries content its template
silently drops: heading/table/prose-paragraph on text-free `graph`/`full`
(link-only lines exempt — they render as the footer; >1 link line is also an
error), `# h1` alongside the kicker on `equation`, image/table on
`prompt`/`code`, image on `equation`. Fix: move it into a `<!-- comment -->`
(speaker notes) or a template with the right slot.

## Notes & footguns

- `createParagraphBullets` consumes the leading tabs used for nesting — bullet
  groups are applied right-to-left so indices stay valid.
- Tagged-template slides (and brand-kit slides) reconstruct from the notes marker
  on pull, so editing them natively in Slides won't survive a `pull` (by design;
  the markdown is the source of truth).
- Numbered lists use `NUMBERED_DIGIT_ALPHA_ROMAN`; there is no dash-bullet preset.
- Images need a Drive-hostable PNG/JPG (SVG must be rendered first, e.g.
  `rsvg-convert`).
