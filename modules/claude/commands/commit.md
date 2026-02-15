# Commit and Push

@description Stage, commit, and push changes with conventional commit messages.

## Steps

1. Run `git status` and `git diff --stat` to understand all changes.
2. Check the current branch. If the repo's CLAUDE.md says not to commit to main, create a feature branch (`<github-username>/<feature-name>` format) first.
3. Review the diff (`git diff` for unstaged, `git diff --cached` for staged) to understand what changed and why.
4. Skip files that contain secrets (`.env`, credentials, tokens). Warn if any are present.
5. Skip `.claude/settings.local.json` — add it to `.gitignore` if not already ignored.
6. Group related changes into logical commits — one concern per commit. If all changes are related, use a single commit.
7. For each commit:
   - Stage the relevant files by name (not `git add -A`)
   - Write an imperative-mood subject line, ≤72 chars
   - Use a HEREDOC for the commit message
8. Push to the current branch with `git push -u origin HEAD`.
9. Show the final `git log --oneline -5` to confirm.

## Commit message style

Match the repository's existing commit style. If no clear convention exists, use:

```
<imperative summary, ≤72 chars>
```

One logical change per commit. Subject describes the *why*, not the *what*.
