---
name: merge-queue
description: Rescue PRs that are stuck in a GitHub merge queue. Use when a PR can't be force-pushed, `gh pr merge --auto` says "already queued", or Vercel preview fails because of a commit-email mismatch. Covers dequeue via GraphQL, force-push, re-enable automerge, and the Vercel commit-email diagnosis.
---

# merge-queue

Repos with a GitHub merge queue enabled reject normal pushes to queued
PR branches, and `gh pr merge --auto` refuses to touch a PR that's
already in the queue. The dance to fix a small issue on a queued PR is:

1. Dequeue the PR (GraphQL mutation — no `gh` shortcut exists).
2. Push your fix (force-with-lease is safe).
3. Re-enable automerge (`gh pr merge --squash --auto`).

If you try to `git push` without dequeueing first, you get:

```
remote:   ... cannot be updated. To modify this branch, dequeue the
remote:   associated pull request.
remote: error: ... protected branch hook declined
```

## Dequeue + force-push + re-enable (copy-paste)

```bash
PR=4197
OWNER=Jack-and-Jill-AI
REPO=ai-recruiter

# 1. Look up the PR node id and confirm it's queued
gh api graphql -f query="query{
  repository(owner:\"$OWNER\",name:\"$REPO\"){
    pullRequest(number:$PR){
      id state isInMergeQueue mergeQueueEntry{id}
    }
  }
}"

# 2. Dequeue (pass the pullRequest node id, not the queue entry id)
PR_NODE_ID=$(gh api graphql -f query="query{
  repository(owner:\"$OWNER\",name:\"$REPO\"){
    pullRequest(number:$PR){id}
  }
}" --jq '.data.repository.pullRequest.id')
gh api graphql \
  -f query='mutation($id:ID!){dequeuePullRequest(input:{id:$id}){mergeQueueEntry{id}}}' \
  -F id="$PR_NODE_ID"

# 3. Push the fix (commit locally first)
git push --force-with-lease

# 4. Re-enable automerge
gh pr merge "$PR" --squash --auto
```

`gh pr merge --disable-auto` does NOT work while a PR is queued — the
API returns "already queued to merge" and leaves the queue entry in
place. You have to use the GraphQL `dequeuePullRequest` mutation.

## Vercel preview failures — the commit-email trap

If CI shows `Vercel – <project>: FAILURE` on every preview, click
through to the error. If it looks like:

> "Setting your commit email address" (link to a GitHub docs page)

…it's **not** a git config issue. Vercel is rejecting the deploy
because the HEAD commit's author email isn't on a GitHub account linked
to the Vercel team. Usually happens when:

- A sub-agent committed with a different `user.email` than your main
  identity.
- A merge-base commit was authored by someone whose Vercel access
  lapsed.

**Diagnosis:**

```bash
git log -1 --format='%ae %an' HEAD
```

**Fix options (in order of least invasive):**

1. Re-author the commit: `git commit --amend --reset-author` (only
   your commits, after confirming `git config user.email` is the
   expected value).
2. Rebase and re-sign the whole branch: `git rebase -i main -x 'git
   commit --amend --no-edit --reset-author'`.
3. Add the offending email to the Vercel team (if it's legitimate).

Vercel preview failures are **not** blocking for turret PRs because
turret's Vercel previews aren't load-bearing — the actual deploy
happens via `wrangler deploy` in the Turret Checks action. If every
other check is green and the only red is three Vercel preview rows,
you can usually merge through regardless.

## When a merged PR still shows "queued"

GitHub's UI lags by a few seconds after `dequeuePullRequest`. If you
try to `git push` immediately after dequeueing and still get the
protected-branch-hook error, wait 2-3 seconds and retry.

## When the merge queue merged your stale commit

If your PR merged before you noticed it was still holding a broken
commit in the queue, you're past the point of dequeueing. Follow the
PR workflow rule in global AGENTS.md instead:

> Before pushing any fix to a branch, check `gh pr view <n> --json
> state,mergedAt`. If the PR is already merged, push to a new branch
> off `main` and open a fresh PR.
