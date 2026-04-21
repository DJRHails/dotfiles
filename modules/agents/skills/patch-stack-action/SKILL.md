---
name: patch-stack-action
description: Manage patch-stack forks — setup, daily patch editing, and sync workflows. Use when a repo references DJRHails/patch-stack-action, has commits prefixed "patch-stack:", or has patch/* branches.
license: MIT
metadata:
  author: DJRHails
  version: "1.0"
---

# Patch Stack

Manage patch-stack forks powered by [DJRHails/patch-stack-action](https://github.com/DJRHails/patch-stack-action).

## When to use

- The repo references `DJRHails/patch-stack-action` in a workflow
- Commits on `main` are prefixed with `patch-stack:`
- The repo has `patch/*` branches
- The user wants to set up a new patch-stack fork

## Concepts

A patch-stack fork maintains a clean separation between upstream code and your changes:

| Branch | What it is |
| --- | --- |
| **`base`** (or configured name) | Read-only mirror of upstream `main`. Updated automatically by the nightly sync. Never commit to this directly. |
| **`patch/*`** | One branch per logical change. Each is rebased onto `base` automatically. This is where you do your work. |
| **`main`** | The integration branch. Built automatically: `base` + all patches squash-merged (prefixed `patch-stack:`). Never commit to this directly except `fork: ` prefixed commits for fork-specific infra. |

**Key rule: `main` is rebuilt from scratch on every sync.** Only `fork: ` prefixed commits and `patch-stack:` squash-merges survive. All real work happens on `patch/*` branches.

## Day-to-day patch editing workflow

### Creating a new patch

Every patch needs three things: a `patch/*` branch from `base`, a push, and a **local PR targeting `base`**.

```bash
# 1. Always branch from base, not main
git checkout -b patch/my-feature origin/base

# 2. Make your changes, commit
git add <files>
git commit -m "feat(scope): description"

# 3. Push
git push origin patch/my-feature

# 4. ALWAYS create a PR targeting base (not main)
gh pr create --head patch/my-feature --base base
```

**The PR against `base` is required.** The sync action uses it to track patch state, generate squash commit messages on `main`, and link to upstream PRs. Without it the patch is invisible to the workflow.

### Editing an existing patch

```bash
# Check out the patch branch
git checkout patch/my-feature

# Or use a worktree to avoid leaving main
git worktree add .data/worktrees/my-feature patch/my-feature
```

Make your changes, commit, and push to the `patch/*` branch. The next sync integrates the update into `main`.

**Never merge a `patch/*` branch into `main` yourself.** The action handles this.

### Using worktrees (recommended)

Worktrees let you edit a patch without switching away from `main`:

```bash
# Create worktree
git worktree add .data/worktrees/<name> patch/<name>

# Work in the worktree
cd .data/worktrees/<name>
# ... edit, commit, push ...

# Clean up when done
cd -
git worktree remove .data/worktrees/<name>
```

### Patch dependencies

Encode dependencies in the branch name with `--` separators:

```
patch/fix-auth                          # root — rebases onto base
patch/fix-auth--improve-token-refresh   # depends on patch/fix-auth
```

### Triggering a sync

```bash
# Manual trigger
gh workflow run patch-stack-sync.yml

# Dry run (preview only, no pushes)
gh workflow run patch-stack-sync.yml -f dry_run=true
```

### After sync: update local main

```bash
git checkout main
git pull --rebase origin main
```

### Commit conventions

- **On `patch/*` branches**: use normal conventional commits
- **On `main` (auto-generated)**: `patch-stack: <description> (#PR)`
- **Fork-specific infra on `main`**: prefix with `fork: ` to survive rebuilds (e.g. `fork: update CI config`)

### What NOT to do

- **Never skip the PR** — every `patch/*` branch must have a PR targeting `base`
- **Never target `main`** with a patch PR — always target `base`
- **Never merge** `patch/*` into `main` manually
- **Never rebase** `main` onto `base` manually
- **Never commit** to `base` — it is a read-only upstream mirror
- **Never commit** to `main` without `fork: ` prefix (it will be dropped on next rebuild)
- **Never force-push** `main` or `base`

## How the nightly sync works

1. **Mirror** — fast-forwards `base` to match upstream
2. **Rebase** — rebases each `patch/*` branch onto updated `base`. Conflicts are resolved automatically using Claude Code.
3. **Rebuild `main`** — starts from `base`, preserves `fork: ` commits, then squash-merges each patch in topological order
4. **Cleanup** — if an upstream PR for a patch is merged or closed, the `patch/*` branch is archived

## Setup (new fork)

Use this section when converting a standard fork into a patch-stack fork.

### Step 1: Gather information

Auto-detect or ask for:

```bash
# Detect fork parent
gh repo view --json parent -q '.parent.owner.login + "/" + .parent.name'

# Detect fork repo
gh repo view --json nameWithOwner -q '.nameWithOwner'
```

- **Upstream repo**: `<UPSTREAM_OWNER>/<UPSTREAM_REPO>`
- **Fork repo**: `<FORK_OWNER>/<FORK_REPO>`
- **Upstream branch**: default `main`
- **Fork base branch**: default `base`

### Step 2: Create the workflow file

Create `.github/workflows/patch-stack-sync.yml`:

```yaml
name: Patch Stack Sync

on:
  schedule:
    - cron: "0 4 * * *" # nightly at 4am UTC
  workflow_dispatch:
    inputs:
      dry_run:
        description: "Dry run — preview only, no pushes or PR mutations"
        type: boolean
        default: false

jobs:
  sync:
    uses: DJRHails/patch-stack-action/.github/workflows/patch-stack-sync.yml@main
    with:
      upstream_repo: <UPSTREAM_OWNER>/<UPSTREAM_REPO>
      upstream_branch: <UPSTREAM_BRANCH>
      fork_repo: <FORK_OWNER>/<FORK_REPO>
      fork_main: main
      fork_base_branch: <FORK_BASE_BRANCH>
      dry_run: ${{ inputs.dry_run || false }}
    secrets:
      app_id: ${{ secrets.PATCH_STACK_APP_ID }}
      app_private_key: ${{ secrets.PATCH_STACK_APP_PRIVATE_KEY }}
      claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### Step 3: Add fork note to README.md

Insert after the first heading:

```markdown
> **Fork note — patch-stack workflow:**
> This is a patch-stack fork of [<UPSTREAM_OWNER>/<UPSTREAM_REPO>](https://github.com/<UPSTREAM_OWNER>/<UPSTREAM_REPO>), managed by [DJRHails/patch-stack-action](https://github.com/DJRHails/patch-stack-action).
>
> **How it works:**
> - The `<FORK_BASE_BRANCH>` branch mirrors upstream `<UPSTREAM_BRANCH>` nightly.
> - Each `patch/*` branch holds a single logical change rebased automatically onto `<FORK_BASE_BRANCH>`.
> - The fork's `main` integrates all patches via squash-merge (commits prefixed `patch-stack:`).
> - Merge conflicts during rebase are resolved automatically using Claude Code.
>
> **Adding a new patch:**
> 1. `git checkout -b patch/my-feature origin/<FORK_BASE_BRANCH>`
> 2. Make changes and push: `git push origin patch/my-feature`
> 3. Create a PR: `gh pr create --head patch/my-feature --base <FORK_BASE_BRANCH>`
>
> **Current patches:** _(update this list as patches are added)_
```

### Step 4: Add CLAUDE.md documentation

If `CLAUDE.md` or `AGENTS.md` exists, add a "Patch-Stack Fork Workflow" section. Otherwise create `CLAUDE.md`. Document:

- Branch layout table (base, patch/*, main)
- How nightly sync works (mirror, rebase, rebuild, cleanup)
- How to create/edit patches
- Patch dependency naming convention
- Commit conventions
- Required secrets table
- Guidelines (never merge manually, never rebase main, fork: prefix)

### Step 5: Create the upstream mirror branch

```bash
git remote add upstream https://github.com/<UPSTREAM_OWNER>/<UPSTREAM_REPO>.git 2>/dev/null || true
git fetch upstream <UPSTREAM_BRANCH>
git branch <FORK_BASE_BRANCH> upstream/<UPSTREAM_BRANCH>
git push origin <FORK_BASE_BRANCH>
```

### Step 6: Commit

```
fork: set up patch-stack fork workflow
```

### Step 7: Create and install the GitHub App

The sync workflow needs a GitHub App to push branches and manage PRs. Walk the user through this:

#### Create the app

1. Go to **https://github.com/settings/apps/new**
2. **Name**: something like `patch-stack-bot` (must be globally unique)
3. **Homepage URL**: `https://github.com/DJRHails/patch-stack-action`
4. **Permissions** (Repository):
   - **Contents**: Read & Write (push branches, create commits)
   - **Pull requests**: Read & Write (create/update/close PRs)
   - **Metadata**: Read-only (required by GitHub)
5. Uncheck "Active" under Webhooks (not needed)
6. Select "Only on this account" under installation access
7. Click "Create GitHub App"

#### Note the App ID

After creation, the **App ID** is shown at the top of the app's General settings page. Save this for the `PATCH_STACK_APP_ID` secret.

#### Generate a private key

On the same General settings page, scroll to "Private keys" and click **"Generate a private key"**. A `.pem` file downloads. The contents of this file are the `PATCH_STACK_APP_PRIVATE_KEY` secret.

#### Make it public (if fork is in a different org)

If the fork repo lives in a different GitHub org/account than where the app was created:

1. Go to the app's **Advanced** settings
2. Click **"Make this GitHub App public"**

This allows other orgs to install it.

#### Install the app on the fork repo

1. Go to the app's **"Install App"** page (sidebar)
2. Click **Install** next to the org/account that owns the fork
3. Select **"Only select repositories"** and pick the fork repo
4. Click **Install**

If the fork is in a different org, have an org admin visit `https://github.com/apps/<app-name>` and click Install.

#### Add repo secrets

Go to the fork repo's **Settings > Secrets and variables > Actions** and add:

| Secret | Value |
| --- | --- |
| `PATCH_STACK_APP_ID` | The App ID from the app's General page |
| `PATCH_STACK_APP_PRIVATE_KEY` | The full contents of the downloaded `.pem` file |
| `CLAUDE_CODE_OAUTH_TOKEN` | Run `claude setup-token` locally and paste the output |

#### Trigger the first sync

```bash
gh workflow run patch-stack-sync.yml
```

Watch the run to confirm it completes successfully:

```bash
gh run list --workflow=patch-stack-sync.yml --limit 1
```
