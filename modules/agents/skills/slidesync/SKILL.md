---
name: slidesync
description: Bidirectional sync between a Slidev markdown deck and Google Slides as native, editable objects (not images). Push markdown -> Slides, pull Slides -> markdown, and round-trip. Use when the user wants to author/version a Google Slides deck from markdown, replicate a deck's styling, or keep a .slidev.md in sync with a presentation. Auth is borrowed from the `gog` CLI (no separate OAuth setup).
version: 1.0.0
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

Script (uv, self-contained deps): `scripts/slidesync.py`.

## Auth (no setup)

Borrowed from `gog`: OAuth client id/secret from
`~/Library/Application Support/gogcli/credentials.json`, refresh token via
`gog auth tokens export`. The stored token already carries `slides`+`drive`
scopes. Requires the **Slides API enabled** on the gog Cloud project.
The account defaults to gog's default account (override with `--account` or
`$SLIDESYNC_ACCOUNT`).

## Commands

| Command | Purpose |
|---------|---------|
| `slidesync.py push <file.slidev.md> [--deck ID] [--new "Title"] [--anchor SLIDE] [--prune]` | md -> Slides |
| `slidesync.py pull <deckId> --out <file.md> [--all]` | Slides -> md (`--all` includes non-managed slides) |
| `slidesync.py roundtrip [--keep]` | self-test: push a sample, pull, assert identical |
| `slidesync.py layouts <deckId>` | list a deck's theme layouts + placeholders |
| `slidesync.py make-templates <deckId>` | inject legacy in-deck `{{token}}` template slides |

`push` resolves the target deck from (in order) `--deck`, `--new`, or a
top-level `deck:` frontmatter key (URL or bare id). Relative image paths resolve
against the markdown file's directory.

```bash
scripts/slidesync.py push deck.slidev.md          # targets `deck:` frontmatter
scripts/slidesync.py push deck.slidev.md --new "Talk"
scripts/slidesync.py pull <id> --out deck.slidev.md
scripts/slidesync.py roundtrip
```

## Idempotent sync (upsert)

Each managed slide is created with `objectId = s2g_<keyHash>_<contentHash>`.
`keyHash` = per-slide `id:` frontmatter, else title slug, else index (survives
edits/reorders); `contentHash` is over a canonical render, so push->pull->push is
a no-op. Diff per run: identical hash -> skip; same key, new content -> replace;
new key -> create. Removed slides are **kept** unless `--prune`. **Only `s2g_`
slides are ever touched** — hand-authored slides are invisible to the sync. A
hidden `<!-- s2g {...} -->` marker in speaker notes carries the human id, image
path, and template vars so `pull` can recover them (3 blank lines below the
real note).

## Markdown dialect

Top-level frontmatter: `theme:`, `deck:`. Slides separated by `---`; each slide
may have its own frontmatter (`id:`, `template:`, `layout:`).

- `# h1` = headline, `## h2` above an h1 = kicker; a lone `##` is the title.
- Bullets `-`/`*`; ordered `1.` (nest with 2-space indent). Inline
  `**bold**` / `*italic*` / `` `code` `` / `[link](url)` (rendered brand-red +
  underlined). GFM tables. `![](path)`
  images (uploaded to Drive). Blank lines preserved as spacing. `<!-- notes -->`
  become speaker notes. `<v-clicks>`/`<div>` are stripped.
- **Internal links:** `[text](#slide-id)` becomes a native Slides link that jumps
  to the slide whose `id:` (or title slug) is `slide-id`. Resolved against the
  whole push set and re-applied on every push, so links survive a target's
  content change. Only body links work (title links are dropped); a target on a
  no-body template (`dark`/`title`/`appendix`/`graph`) is warned and skipped.

### Built-in brand kit (IBM Plex; red #C0392B kicker)

Select per slide via `template:` — native styled boxes, no in-deck templates:

| `template:` | look |
|-------------|------|
| `dark` / `title` | dark #1E2024 bg, kicker + big white headline (centred) |
| `appendix` | light #FAFAFA bg, kicker + big ink headline |
| `question` / `label` | kicker + headline + **centred** body |
| `topic` | kicker + headline + **left** body (and/or image) |
| `content` | red kicker-as-title + left body |
| `graph` / `full` | **text-free**: a single image scaled to fill the page (aspect preserved, centred, thin margin); title/body ignored — for self-titled figures |
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

## Notes & footguns

- `createParagraphBullets` consumes the leading tabs used for nesting — bullet
  groups are applied right-to-left so indices stay valid.
- Tagged-template slides (and brand-kit slides) reconstruct from the notes marker
  on pull, so editing them natively in Slides won't survive a `pull` (by design;
  the markdown is the source of truth).
- Numbered lists use `NUMBERED_DIGIT_ALPHA_ROMAN`; there is no dash-bullet preset.
- Images need a Drive-hostable PNG/JPG (SVG must be rendered first, e.g.
  `rsvg-convert`).
