# Claude Code Preferences

- When I report a bug, don't start by trying to fix it. Instead, start by writing a test that reproduces the bug. Then, have subagents try to fix the bug and prove it with a passing test.

## Project Organisation

- **Use Go-style folder structure for repositories in ~/projects**
- Organise repositories using the pattern: `~/projects/domain.com/organisation/repository`
- Examples:
  - `~/projects/github.com/TypeCellOS/BlockNote`
  - `~/projects/registry.tiptap.dev/@tiptap-pro/extension-ai`

## Session Insights & Memory

- After completing significant work, or the session required a user intervention / rejected tool usage, offer to review and save insights to CLAUDE.md

## Markdown Structure (mdstruct)

Use `mdstruct` to split large markdown files into hierarchical folder structures, or join them back.

**Split a file by headers:**
```bash
mdstruct split path/to/file.md        # splits into path/to/file/
mdstruct split path/to/file.md -l 3   # split up to H3 level
```

**Join files back:**
```bash
mdstruct join path/to/folder/         # joins back into path/to/folder.md
```

**Auto-detect:**
```bash
mdstruct auto path/to/file            # splits .md file or joins folder
```

- Useful for breaking up large idea/note files into individual topics
- Each H2 becomes its own file, numbered for ordering
- Creates a README.md with the top-level content
- Original file is backed up to `/tmp/mdstruct/`
- **Parallel sub-agents**: Split a file, spawn sub-agents to work on individual sections concurrently, then join back
