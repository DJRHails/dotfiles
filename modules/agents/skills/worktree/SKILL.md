---
name: worktree
description: Manage git worktrees — setup and cleanup. Use when the user asks to clean up, prune, create, or sync worktrees, create worktrees for open PRs, or create a worktree. Also load proactively when the session starts inside a worktree (working directory contains .data/worktrees/).
---

# Worktree Management

A single workflow that keeps worktrees in sync with open PRs: removes stale
ones, creates missing ones, and ensures every worktree has working tooling.

## When to use

- "clean up / prune worktrees"
- "create worktrees for my PRs"
- "set up worktrees"
- Periodic housekeeping after a batch of merges

## Procedure

Run all steps in order. Each step feeds into the next.

---

### Step 1 — Inventory

Collect current state in parallel:

```bash
# All worktrees (skip main — first line)
git worktree list

# All open PRs for current user
gh pr list --state open --author "@me" --json number,title,headRefName,url

# All merged PRs (to cross-reference stale worktrees)
gh pr list --state merged --author "@me" --json number,headRefName --limit 50
```

Derive `MAIN` path:
```bash
MAIN=$(git worktree list | head -1 | awk '{print $1}')
```

---

### Step 2 — Identify stale worktrees

A worktree is **stale** (safe to remove) if **either**:
- Its branch HEAD is an ancestor of `main`:
  ```bash
  git merge-base --is-ancestor <commit> main
  ```
- Its associated PR is `MERGED` or `CLOSED`

Never remove a worktree whose PR is still `OPEN`.

---

### Step 3 — Identify missing worktrees

A worktree is **missing** if an open PR's branch has no corresponding entry in
`git worktree list`.

---

### Step 4 — Report and confirm

Show one combined table before making any changes:

| Branch | Worktree path | PR | Action |
|--------|---------------|----|--------|
| `feat/foo` | `.data/worktrees/feat-foo` | #123 MERGED | **Remove** |
| `fix/bar` | *(none)* | #456 OPEN | **Create** |
| `feat/baz` | `.data/worktrees/feat-baz` | #789 OPEN | Keep |

Ask the user to confirm before proceeding.

---

### Step 5 — Remove stale worktrees

```bash
git worktree remove --force <path>
```

Use `--force` — worktrees often have untracked files (build artifacts, `.env`).
Offer to delete the local branch too:

```bash
git branch -d <branch>
```

---

### Step 6 — Create missing worktrees

Use the `worktree::create` script which handles the full flow: checkout the
branch, copy-on-write `node_modules`, and copy untracked config files.

**Always pass all branches in a single invocation** — the script batches
network I/O and parallelises the expensive CoW bootstrap phase:

```bash
SKILL_DIR="$HOME/.claude/skills/worktree"
bash "$SKILL_DIR/scripts/worktree-create.sh" <branch-1> <branch-2> ...
```

The script runs in two phases:
1. **Sequential (git lock):** `git pull` once, batch-fetch all branches in one
   network round-trip, then `git worktree add` for each branch.
2. **Parallel bootstrap:** CoW-copy `node_modules`, config files, and
   `direnv allow` — all branches bootstrapped concurrently.

Per-worktree details:
- Creates the worktree under `.data/worktrees/<branch-with-slashes-replaced>`
- CoW-copies all root `node_modules` directories from the main worktree
- CoW-copies untracked config files (`.envrc`, `.env`, `.tool-versions`, etc.)
- Runs `direnv allow` if `.envrc` was copied

On APFS (macOS), `cp::cow` uses `clonefile` under the hood — near-instant and
zero extra disk until files diverge. Each worktree gets its own independent
`node_modules`, so `pnpm install` in one worktree won't affect others.

Pre-commit and pre-push hooks (lefthook, husky, etc.) shell out to `tsc`,
`biome`, `eslint`, and friends — all of which `ENOENT` without `node_modules`.
The CoW copy ensures hooks work without `--no-verify`.

---

### Step 7 — Final report

```
Removed:  feat/foo  (#123)
Created:  fix/bar   (#456)  → .data/worktrees/fix-bar
Kept:     feat/baz  (#789)
Copied:   12 node_modules (CoW) across 3 worktrees
```

---

## Notes

- The main worktree (first `git worktree list` entry) is never touched
- Detached HEAD worktrees: check if the commit is an ancestor of `main`
- If `gh` is unavailable, fall back to git-only merge checks
- Always place worktrees under `.data/worktrees/` to keep the repo root clean
</content>
