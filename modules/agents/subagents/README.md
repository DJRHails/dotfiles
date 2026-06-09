# Vendored subagents

Subagent definitions consumed by the `review-pr` skill, vendored from the
official `pr-review-toolkit` plugin
(`claude-plugins-official/plugins/pr-review-toolkit/agents`) so the skill
resolves them by bare `subagent_type` without that plugin being enabled —
including inside gantry worker sandboxes that install these dotfiles.

This `subagents/` dir is symlinked to `~/.claude/agents/` (see `symlinks.conf`),
the location Claude Code scans for subagents. It is named `subagents/` here for
clarity; identity comes from each file's `name:` frontmatter, not the path.

Re-sync: copy the updated `*.md` files from the plugin's `agents/` dir.
