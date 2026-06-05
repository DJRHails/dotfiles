---
name: cdn-upload
description: Upload local files (figures, images, any asset) to the user's public CDN at cdn.hails.info (Cloudflare R2) and get back public https URLs. Use when an image/file needs a public URL — e.g. embedding a figure inline in a PRIVATE-repo GitHub PR/issue description (private-repo raw/blob links do NOT render; a public cdn.hails.info URL does, via GitHub's camo proxy), sharing a screenshot, or any "host this so it has a URL" need. Backed by the kb project's R2 scheme.
---

# cdn-upload — public URLs for local files via cdn.hails.info

`cdn.hails.info` is a public Cloudflare R2 bucket (`r2:cdn-hails-info`). Upload a file and it is
reachable at `https://cdn.hails.info/<key>`. Because the URL is public, GitHub renders it inline in
markdown **even for private repos** (where committed/`raw.githubusercontent.com` image links 404 or
are blocked by the camo proxy).

## Use it

```bash
"$(dirname "")"/scripts/cdn-upload path/to/figure.png [more.png ...]
# prints one https://cdn.hails.info/img/<sha256[:32]>.png per file on stdout
```

The script (mirrors `DJRHails/kb` `bin/r2_upload.py`):

- **Content-addressed**: key is `img/<sha256[:32]><ext>`, so identical bytes collapse to one object
  and re-uploads are idempotent (same URL every time).
- **Immutable cache header** on upload (`Cache-Control: public, max-age=31536000, immutable`).
- **Routing**: uses a local `rclone` if the `r2:` remote is configured; otherwise scps the file to
  `trifle` (the user's Mac, where `rclone` + the `r2:` remote live) and uploads from there. So it
  works from any tailnet host (e.g. `bonbon`).

## Embedding in a GitHub PR/issue (the common case)

1. `url=$(.../scripts/cdn-upload figures/foo.png)`
2. Put `![caption]($url)` in the PR/issue body.
3. Update an existing PR body with the REST API (avoids a `gh pr edit` bug that fails on
   Projects-classic GraphQL): `gh api --method PATCH repos/<owner>/<repo>/pulls/<n> -F body=@body.md`.

## Notes

- Verify a URL is live: `curl -s -o /dev/null -w '%{http_code} %{content_type}' "$url"` → `200 image/png`.
- The full `kb` flow (`bin/r2_upload.py <dir>`) also rewrites markdown image refs in-place and keeps
  a content registry; this skill is just the upload primitive for one-off files.
