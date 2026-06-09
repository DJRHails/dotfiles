# Vendored subagents

Subagent definitions consumed by the `review-pr` skill, vendored from the
official `pr-review-toolkit` plugin
(`claude-plugins-official/plugins/pr-review-toolkit/agents`) so the skill
resolves them by bare `subagent_type` without that plugin being enabled —
including inside gantry worker sandboxes that install these dotfiles.

Re-sync: copy the updated `*.md` files from the plugin's `agents/` dir.
