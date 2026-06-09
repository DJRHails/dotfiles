# Vendored subagents

Subagent definitions consumed by the `review-pr` skill, vendored from the
official `pr-review-toolkit` plugin
(`claude-plugins-official/plugins/pr-review-toolkit/agents`) so the skill
resolves them by bare `subagent_type` without that plugin being enabled —
including inside gantry worker sandboxes that install these dotfiles.

The `agents/` root is symlinked into `~/.claude/agents/` (see `symlinks.conf`)
and scanned recursively; agent identity comes from the `name:` frontmatter,
not the path, so this `subagents/` subfolder is purely organizational.

Re-sync: copy the updated `*.md` files from the plugin's `agents/` dir.
