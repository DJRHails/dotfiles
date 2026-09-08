---
name: overleaf
description: Read and write Overleaf projects from the CLI using an existing web session — list and create projects, list/read/write/delete files, mirror a local directory into a project, compile it and pull the PDF. Works on a free account, where Overleaf's git and GitHub bridges are premium-only. Use when the user references an Overleaf project or URL, wants to push a paper or figures to Overleaf, sync a built LaTeX tree there, check whether a project compiles, or fetch its PDF or zip.
---

# Overleaf CLI

Overleaf publishes no API, and both its git bridge and its GitHub sync are premium
features. `overleaf.py` drives the same endpoints the web editor drives, authenticated by
the `overleaf_session2` cookie of a logged-in browser — so a **free account** gets
scriptable read and write access, including the directory mirroring the git bridge would
otherwise be for.

Sibling of the [`slack`](../slack/SKILL.md) skill and built the same way: a PEP 723
`uv run` script, one typed pydantic model per payload, `typer` sub-apps, an env-file
preload, and the same "runs headless off-box" session path.

## Prerequisites

- Signed into `https://www.overleaf.com/` in a browser, and its session cookie put where
  the CLI can read it (see [Auth](#auth)). Nothing else — no premium plan, no token, no
  OAuth app.
- `uv` installed. Dependencies are inline: `pydantic`, `requests`, `rich`, `typer`,
  `websocket-client`.

## Commands

All commands take `PROJECT` as **a project id, a project URL, or a name** (matched
exactly, then case-insensitively, then by substring; an ambiguous name lists the
candidates instead of guessing). Top-level `-v` prints session details to stderr.

```bash
./overleaf.py session                         # who the session belongs to (the quickest check)

./overleaf.py projects list [--json] [--archived]
./overleaf.py projects new "Paper title"      # prints the new project's id and URL

./overleaf.py files ls   <project> [--json]   # paths with their entity ids and kinds
./overleaf.py files read <project> sections/intro.tex [-o out.tex]
./overleaf.py files write <project> main.tex --from ./built/main.tex [--yes]
./overleaf.py files rm   <project> figures/old.png [--yes]

./overleaf.py push <project> ./staged [--prune] [--dry-run] [--yes]
./overleaf.py compile  <project> [--pdf paper.pdf] [--logs]
./overleaf.py download <project> [-o project.zip]
```

### `push` — mirror a directory into a project

The reason this skill exists. `push` walks a local directory, diffs it against the
project, and uploads only what differs:

- **Content is compared, not timestamps.** Every path present on both sides is downloaded
  and compared, so an unchanged directory pushes nothing and leaves the project history
  alone. A trailing-newline-only difference does not count as a change: Overleaf stores a
  text doc as a line array and rebuilds it on download, which can add or drop the final
  newline with no edit having happened.
- **Folders are created server-side.** Each file posts to the project root carrying its
  `relativePath`, exactly as the editor's own folder-drop upload does, and Overleaf walks
  the path creating any missing folder.
- **Existing files are replaced in place**, keeping their entity id and their history — so
  a repeated push is idempotent rather than a pile of duplicates.
- **`--prune` deletes project files the directory no longer has.** Off by default, and the
  plan always lists the deletions before anything happens.
- **Dot-prefixed names are skipped** at every level (`.git`, `.DS_Store`, editor state).
- `--dry-run` prints the plan and stops. Every write command prompts unless `--yes`.

```bash
./overleaf.py push 6aa025104d6398f6e090368d ./manuscript/.build/overleaf --prune --dry-run
```

### `compile` — does it actually build?

`compile` runs the project's LaTeX **on Overleaf** and reports the status, so no local TeX
install is needed to know whether a push compiles. It exits non-zero on failure and prints
the LaTeX log (always with `--logs`, automatically on failure). `--pdf <path>` saves the
PDF the compile produced.

## Auth

The session comes from, in order:

1. `$OVERLEAF_SESSION_COOKIE`
2. `~/.config/overleaf/session`

plus `$OVERLEAF_GCLB_COOKIE` / `~/.config/overleaf/gclb` for the optional load-balancer
pin, and `~/.config/overleaf/env` (`export VAR=value` lines) which is pre-loaded into the
environment so a headless host needs no wrapper. Existing variables always win.

Because the credential is supplied rather than scraped, **the CLI runs anywhere** — a
server, a container, an ssh session whose macOS Keychain is unreachable — not only on the
machine holding the browser.

**Capturing the cookie.** In the browser: DevTools → Application → Cookies →
`https://www.overleaf.com` → copy `overleaf_session2`. Then one command on the host that
will run the CLI (it echoes nothing and keeps the file private):

```bash
mkdir -p ~/.config/overleaf && read -rs -p 'overleaf_session2: ' s && \
  printf '%s' "$s" > ~/.config/overleaf/session && chmod 600 ~/.config/overleaf/session && \
  echo && ./overleaf.py session
```

The cookie is a **full-account bearer credential** — treat it like a password, keep it out
of shell history and out of any repo, and re-capture it when it expires. Every command
funnels a logged-out response into one message naming that fix, so an expired cookie never
reads as "the project is empty".

`$OVERLEAF_HOST` points the whole CLI at a self-hosted instance
(`OVERLEAF_HOST=latex.example.org`); the cookie domain follows it.

## When to use this skill

- **Use** when: the user hands over an Overleaf URL or project name; a paper, figure, or
  built LaTeX tree needs to get into Overleaf; a co-author's project needs reading from
  the CLI; you need to know whether a project compiles, or want its PDF or zip.
- **Prefer the git bridge instead** when the account actually has premium — it is
  Overleaf's supported interface, and `git` gives real history and merges. This skill is
  for the free-plan case, and for scripted one-way mirroring where a git remote is
  overkill.
- **Writes are fenced by a confirmation prompt** (`files write`, `files rm`, `push`) and
  `push --prune` lists every deletion first. An Overleaf project shared with co-authors is
  other people's working surface: confirm the plan with them before pushing over it, and
  remember the push is one-way — an edit made in the Overleaf editor is overwritten, not
  merged.

## Examples

```bash
# Where does this URL point, and what is in it?
./overleaf.py files ls https://www.overleaf.com/project/6aa025104d6398f6e090368d

# Mirror a built manuscript in, then prove it compiles and keep the PDF
./overleaf.py push "Monitor Bycatch" ./manuscript/.build/overleaf --prune --yes
./overleaf.py compile "Monitor Bycatch" --pdf /tmp/monitor-bycatch.pdf

# Read one file out of a co-author's project
./overleaf.py files read "vlm-judges-paper-iclr" sections/method.tex

# Swap a single figure without touching anything else
./overleaf.py files write "Monitor Bycatch" figures/roc.png --from ./figures/roc.png --yes
```

## Gotchas

- **The file tree needs the socket, the rest does not.** Overleaf has no HTTP endpoint
  that returns entity **ids** (`/project/<id>/entities` gives paths without them), and
  uploads and deletes both need one, so the tree is read from the `joinProjectResponse`
  frame the editor's socket.io connection is handed. That is the one fragile surface here;
  everything else is a plain authenticated HTTP call.
- **The load-balancer cookie matters for the socket.** Overleaf sits behind Google's load
  balancer, which pins a session to one backend via `GCLB`. Without it a socket upgrade
  can land on a backend that does not know the session — set `$OVERLEAF_GCLB_COOKIE` if
  `files ls` or `push` fails while `session` and `projects list` work.
- **No response cache, deliberately** — unlike the slack CLI, whose cache pays for token
  probing and hundred-page pagination. Here every call is one cheap request whose whole
  value is being current: a cached project list would hide a project created a minute ago,
  and a cached file body would make `push` skip a real edit. The one held value is the
  CSRF token, for the life of the process, so a push of two dozen files does not load the
  editor page two dozen extra times to re-read it.
- **Page shape is Overleaf's, and it can change.** Project and CSRF state is read from the
  `ol-*` meta tags the editor bootstraps itself from. A missing meta fails loudly, naming
  what it found, rather than returning something empty.
- **`push` is one-way.** There is no pull-and-merge; to bring Overleaf-side edits back,
  `files read` them (or `download` the zip) and port them by hand. The diff reads each
  doc's *persisted* content, so a co-author's still-unsaved editor changes can read as
  unchanged and then be overwritten — push when nobody is mid-edit.
- **`--prune` deletes files, not folders.** A folder whose contents were all pruned stays
  in the project, empty. That is cosmetic and deliberate: deleting a folder in Overleaf
  takes everything under it, which is the wrong instrument for a diff computed over files.
  Remove one with `files rm <project> <folder>`.
- **Rate limits are per project and generous but real** — Overleaf allows 500 file uploads
  per 15 minutes and 20 project creations per minute. A very large mirror can trip the
  first; `push` uploads only what changed, which is usually enough to stay under it.

## Prior art

[`pyoverleaf`](https://github.com/jkulhanek/pyoverleaf) covers the same endpoints and
auto-reads Chrome/Firefox cookies, and was the reference for the socket and upload details
here. This skill differs where it matters for agent use: the credential is supplied rather
than lifted out of a browser store, the payloads are typed and fail loudly on drift, and
the content-diffing `push`, `compile`, and project resolution by name are the commands the
workflow actually needs.

## Local files

- `overleaf.py` — the CLI (PEP 723 inline deps, runs via `uv run`)
- `test_overleaf.py` — 52 offline tests; every HTTP call is intercepted with `responses`
  and the socket frames come from a fixture, so the suite needs no session:

```bash
uv run --no-project --with pytest,responses,pydantic,requests,rich,typer,websocket-client \
  pytest test_overleaf.py -q
```
