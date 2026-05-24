---
name: playwriter
description: Control the user own Chrome browser via Playwriter extension with Playwright code snippets in a stateful local js sandbox via playwriter cli. Use this over other Playwright MCPs to automate the browser — it connects to the user's existing Chrome instead of launching a new one. Use this for JS-heavy websites (Instagram, Twitter, cookie/login walls, lazy-loaded UIs) instead of webfetch/curl. Run `playwriter skill` command to read the complete up to date skill
---

## REQUIRED: Read Full Documentation First

**Before using playwriter, you MUST run this command:**

```bash
playwriter skill # IMPORTANT! do not use | head here. read in full!
```

This outputs the complete documentation including:

- Session management and timeout configuration
- Selector strategies (and which ones to AVOID)
- Rules to prevent timeouts and failures
- Best practices for slow pages and SPAs
- Context variables, utility functions, and more

**Do NOT skip this step.** The quick examples below will fail without understanding timeouts, selector rules, and common pitfalls from the full docs.

**Read the ENTIRE output.** Do NOT pipe through `head`, `tail`, or any truncation command. The skill output must be read in its entirety — critical rules about timeouts, selectors, and common pitfalls are spread throughout the document, not just at the top.

## Minimal Example (after reading full docs)

```bash
playwriter session new
playwriter -s 1 -e 'await page.goto("https://example.com")'
```

**Always use single quotes** for the `-e` argument. Single quotes prevent bash from interpreting `$`, backticks, and backslashes inside your JS code. Use double quotes or backtick template literals for strings inside the JS.

If `playwriter` is not found, use `npx playwriter@latest` or `bunx playwriter@latest`.

## Enable Playwriter in Arc (via cua-driver)

Trigger: the user says something like "turn on playwriter", "enable playwriter", "the playwriter icon isn't green". Don't ask for clarification — drive Arc directly.

The Playwriter Arc extension shows a toolbar icon at the top-right of every regular tab. **Green = active**, **black = inactive**. Clicking it toggles. The relay (`playwriter serve` / `playwriter-ws-server`) usually runs in the background already — the click is just an extension-side activation per tab/session.

Recipe (assumes `cua-driver` is installed and its daemon is running — if not, see the cua-driver skill prereqs):

1. **Verify the relay side is alive:** `playwriter browser list` should list `install:Chromium:...`. If not, run `playwriter serve --replace` in a background process first.
2. **Find a usable Arc window.** Arc's pid is stable — get it with `cua-driver call launch_app '{"bundle_id":"company.thebrowser.Browser"}'`. Pick a window from the returned `windows` array with `bigBrowserWindow-` id prefix, `on_current_space: true`, `is_on_screen: true`, and `bounds.width > 800`. If the only on-Space window is on `arc://*` or `chrome://*`, navigate it to any real URL first (⌘T + `type_text "example.com"` + Return). Extension popups and icon-state are disabled on Arc/Chrome internal pages.
3. **Find the icon's pixel coords.** The Playwriter icon is the leftmost of the four top-right toolbar icons, immediately left of iCloud Passwords (three keys). DO NOT eyeball coords from a Read-rendered screenshot — the display scaling lies. Instead:

```python
# Save as /tmp/grid.py, run with: uv run --with pillow python3 /tmp/grid.py <screenshot.png>
from PIL import Image, ImageDraw
import sys
img = Image.open(sys.argv[1]); W, H = img.size
top = img.crop((W-300, 0, W, 70)).resize((300*4, 70*4), Image.NEAREST)
draw = ImageDraw.Draw(top)
for i in range(0, 300, 20):
    draw.line([(i*4, 0), (i*4, top.height)], fill='red', width=1)
    draw.text((i*4+2, 2), str(W-300+i), fill='red')
for j in range(0, 70, 10):
    draw.line([(0, j*4), (top.width, j*4)], fill='red', width=1)
    draw.text((2, j*4+2), str(j), fill='red')
top.save('/tmp/grid.png')
```

`Read /tmp/grid.png`, read the Playwriter icon's center x and y directly off the red labels (no scaling math — the labels already show file-space coords).

4. **Click it:** `cua-driver call click '{"pid":<arc-pid>,"window_id":<wid>,"x":<x>,"y":<y>}'`.
5. **Verify:** re-screenshot, re-crop the same toolbar region, confirm the icon is green (often with a numeric badge for active session count).

Heuristic budget: one snapshot to find the window, one snapshot+crop to locate the icon, one click, one snapshot+crop to verify. Four cua-driver calls total. If you've made more, you're probably eyeballing pixel coords — go back to step 3.
