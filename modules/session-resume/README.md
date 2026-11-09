# Resume Claude and Codex sessions by ID

`claude::resume <id-or-prefix> [options...]` and
`codex::resume <id-or-prefix> [options...]` accept either tool's session ID.
Both enter the recorded working directory before launching. Claude sessions
retain their owning config profile (`.claude`, `.claude-ant`, `.agents`, or
`CLAUDE_CONFIG_DIR`); Codex respects `CODEX_HOME`.

Install the converter on each host once:

```sh
bash "$DOTFILES/modules/session-resume/install.sh"
```

The installer pins [ai-session-bridge](https://github.com/bakhtiersizhaev/ai-session-bridge)
to `e7f1868bb9ae1bc213307a86e16465887b78acd9` under
`${XDG_DATA_HOME:-~/.local/share}/agent-session-bridge`. It requires git, npm,
and Node 22.5+ for Codex database registration.

When the ID exists only in the other tool, the helper writes a native target
transcript and registers its history before resuming. Conversation messages
and supported tool calls/results are converted, rather than supplied as an
initial prompt. The source transcript is left intact. Conversion limitations
reported by the converter are printed before launch: vendor-specific state,
encrypted reasoning, and unsupported record types cannot all transfer.

Both copies keep the same UUID. Subsequent calls resume an existing target
copy without reconverting or overwriting its continued history. They are
independent conversations after conversion, not a live two-way sync.
Prefixes must be at least four characters and unambiguous across both tools;
subagent transcripts are excluded. Conversion defaults to the active Claude
config directory, or `~/.claude`; set `CLAUDE_CONFIG_DIR=~/.claude-ant` to
choose that profile when importing from Codex.

Open a new shell to load the commands, or source the alias files:

```sh
source "$DOTFILES/modules/claude/aliases.zsh"
source "$DOTFILES/modules/codex/aliases.zsh"
```

Run `zsh -f tests/claude-resume.test.zsh` and
`python3 tests/session-resume.test.py` to check ID resolution, routing, and
native conversion. Conversion tests use synthetic transcripts in temporary
homes and the installed converter. Where Codex is installed, a native
`thread/resume` check also loads the converted history through its app server,
without starting a model turn or spending tokens.
