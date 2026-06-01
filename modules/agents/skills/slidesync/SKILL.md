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
  `**bold**` / `*italic*` / `` `code` `` / `[link](url)`. GFM tables. `![](path)`
  images (uploaded to Drive). Blank lines preserved as spacing. `<!-- notes -->`
  become speaker notes. `<v-clicks>`/`<div>` are stripped.

### Built-in brand kit (IBM Plex; red #C0392B kicker)

Select per slide via `template:` — native styled boxes, no in-deck templates:

| `template:` | look |
|-------------|------|
| `dark` / `title` | dark #1E2024 bg, kicker + big white headline (centred) |
| `appendix` | light #FAFAFA bg, kicker + big ink headline |
| `question` / `label` | kicker + headline + **centred** body |
| `topic` | kicker + headline + **left** body (and/or image) |
| `content` | red kicker-as-title + left body |

Slides with no `template:` fall back to a generative path (section /
TITLE_AND_BODY / table / image) that also brands bg + IBM Plex.

## Notes & footguns

- `createParagraphBullets` consumes the leading tabs used for nesting — bullet
  groups are applied right-to-left so indices stay valid.
- Tagged-template slides (and brand-kit slides) reconstruct from the notes marker
  on pull, so editing them natively in Slides won't survive a `pull` (by design;
  the markdown is the source of truth).
- Numbered lists use `NUMBERED_DIGIT_ALPHA_ROMAN`; there is no dash-bullet preset.
- Images need a Drive-hostable PNG/JPG (SVG must be rendered first, e.g.
  `rsvg-convert`).
