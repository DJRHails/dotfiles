---
name: worktree-cleanup
description: Manage git worktrees. Use when the user asks to clean up worktrees, prune worktrees, check which worktrees are merged, or create worktrees for open PRs. Lists all worktrees, checks if their branches are merged into main (or have merged PRs), removes merged ones, and can create worktrees for open PRs missing one.
---

# Worktree Management

Audit, clean up, and create git worktrees.

## When to use

- User asks to "clean up worktrees", "prune worktrees", or "check worktrees"
- User asks to create worktrees for open PRs/branches
- After merging PRs, to remove stale worktrees
- Periodic housekeeping

## Procedure

### 1. List worktrees

```bash
git worktree list
```

Skip the main worktree (first entry). Collect the paths of all secondary worktrees.

### 2. Check merge status

For each worktree, check two things:

**a) Is the branch ancestor of main?**

```bash
git merge-base --is-ancestor <commit> main && echo "MERGED" || echo "NOT MERGED"
```

**b) Does it have a merged PR?** (if `gh` is available)

```bash
gh pr list --head "<branch>" --state all --json number,title,state,url
```

A worktree is safe to remove if **either**:
- Its HEAD is an ancestor of `main`, OR
- Its associated PR state is `MERGED`

### 3. Report

Show a summary table before removing anything:

| Worktree | Branch | Merged into main? | PR Status |
|----------|--------|--------------------|-----------|

### 4. Confirm and remove

Ask the user for confirmation, then remove merged worktrees:

```bash
git worktree remove --force <path>
```

Use `--force` since worktrees often have untracked files (build artifacts, `.env`, etc.).

### 5. Clean up orphan branches (optional)

After removing worktrees, offer to delete the local branches too:

```bash
git branch -d <branch>
```

---

## Creating Worktrees for Open PRs

### 1. List open PRs

Default to the current user's PRs only. Use `@me` unless a different author is specified:

```bash
gh pr list --state open --author "@me" --json number,title,headRefName,url
```

### 2. Check existing worktrees

```bash
git worktree list
```

Skip branches that already have a worktree.

### 3. Create missing worktrees

For each branch that needs a worktree:

```bash
git fetch origin <branch>
git worktree add .data/worktrees/<short-name> <branch>
```

Derive `<short-name>` from the branch name (e.g. `feat/turret-event-queue` → `feat-event-queue`, `fix/linear-turnstile-auth` → `fix-linear-turnstile-auth`).

### 4. Report

Show a summary table of created worktrees:

| Worktree | Branch | PR |
|----------|--------|----|

---

## Notes

- Never remove worktrees with open PRs unless the user explicitly asks
- The main worktree cannot be removed
- Detached HEAD worktrees: check if the commit is an ancestor of main
- If `gh` is not available, fall back to git-only merge checks
- Place worktrees under `.data/worktrees/` to keep the repo root clean
