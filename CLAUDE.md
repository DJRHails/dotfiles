# dotfiles

Personal dotfiles, checked out at `~/.files`. Modules live under `modules/<name>/`; agent skills
under `modules/agents/skills/` (symlinked into `~/.claude/skills`, `~/.agents/skills`, …).

## This repo is PUBLIC — keep everything plaintext generic

Glassine (`filter=glassine` in `.gitattributes`) encrypts sensitive files at rest, but **git
metadata is always plaintext**: PR titles and descriptions, commit messages, branch names,
review comments, issue text, and `.gitattributes` paths themselves.

- Before writing any of those, check whether the change touches an encrypted path
  (`git check-attr filter -- <path>`). If it does, describe it generically — "update an
  encrypted skill" — and put the real rationale inside the encrypted file.
- Never name hostnames (including this machine's), device models or IPs, tailnet names,
  private repos, internal services, credentials, or what a device/service is used for.
- The attribution footer on PRs/comments stays **host-free** here: `_[via claude](<link>)_`,
  not `claude @ <host>`.
- Branch names are kept on the PR forever, even after deletion — pick a generic one
  (`skill-update`) before the first push; there is no after-the-fact fix.
- If something leaky is already pushed: rewrite the PR title/body via
  `gh api --method PATCH repos/DJRHails/dotfiles/pulls/<n>`, and before merging replace the
  commit message (same tree, force-push) so the squash commit on `main` is generic too.

## Git mechanics

- **Parallel sessions leave unpushed commits on local `main`.** Check
  `git log --oneline origin/main..HEAD` before building a branch; never push commits that aren't
  yours. To open a PR without dragging them along, build the commit on `origin/main` with a
  temporary index (`GIT_INDEX_FILE=… git read-tree origin/main`, `git update-index --cacheinfo`,
  `git write-tree`, `git commit-tree -p origin/main`) and push `<sha>:refs/heads/<branch>`.
- **Encrypted blobs:** `git show`/`git cat-file -p` print ciphertext. Read plaintext with
  `git cat-file --filters <rev>:<path>`; create an encrypted blob from a working-tree file with
  `git hash-object -w --path=<path> <file>` (the `--path` applies the clean filter).
- **Glassine ciphertext is non-deterministic**: re-encrypting identical plaintext gives a new
  blob, so `git status`/`git diff --stat` can report changes that are ciphertext-only. Compare
  plaintext (`git cat-file --filters`) before believing a diff; `git restore --staged` clears
  index-only noise.
- In zsh, `"$var:refs/…"` applies the `:r` modifier to `$var` — write `"${var}:refs/…"`.
- Commit with explicit pathspecs (`git commit -- <paths>`): other sessions stage files in the
  shared index.
