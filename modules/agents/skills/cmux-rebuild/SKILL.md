---
name: cmux-rebuild
description: "Manage the user's durable dev sessions — zellij sessions on remote hosts (bonbon, taffy) reached over mosh, plus the local host's (trifle) own detached zellij sessions, surfaced as cmux tabs via `ssh::durable` / `zellij::resume`. Load when the user wants to rebuild/resurrect lost cmux durable surfaces after a cmux restart or a mass disconnect, resume detached local zellij sessions, reconnect/sort sessions into per-repo cmux workspaces, retitle durable tabs, reap orphaned mosh-servers, judge dead claude/pi sessions from their transcripts and resume the unfinished ones (claude::resume / pi::resume, local or via a remote zellij layout), or understand the `ssh::durable` picker and its green-● connected indicator. Triggers: 'ssh::durable', 'durable sessions', 'resurrect/rebuild cmux', 'cmux-resurrect', 'resume unfinished claude/pi sessions', 'lost my bonbon connections', 'reap mosh-servers', 'the green dot'."
---

# cmux durable sessions

Dev work lives in **zellij sessions** named `cmux-<host>-<id>`. Remote hosts (`bonbon`, `taffy`)
are reached over **mosh** (survives high-redraw TUIs; cmux's ws relay adds per-keystroke latency)
— each surfaced as a cmux tab running `mosh <host> -- zellij attach <session>`. The local host
(`trifle`) auto-attaches a local zellij wrapper in every terminal surface. Zellij sessions persist
across everything; only the cmux surfaces and mosh transports come and go.

Code: `modules/zellij/` — `mosh-zellij.zsh` (`ssh::durable` picker + `zellij::resume`),
`durable-remote.sh` (remote menu/preview/reap), `auto-attach.zsh` (attach + de-nest handoff).
`claude::resume` / `pi::resume` (modules/claude, modules/pi aliases) resolve a session id to its
transcript, cd to its recorded cwd, and route the owning config dir.

**TMPDIR rule:** every local `zellij` invocation needs `TMPDIR=/tmp` — the socket dir follows
TMPDIR, and a surface shell's macOS default (`/var/folders/…`) silently sees zero sessions. The
scripts force it; do the same in ad-hoc commands.

## Attach: ssh::durable and zellij::resume

`ssh::durable <host>` — fzf picker of the host's live sessions (`<cwd> · <AI title>` with a dim
searchable id tail). Green **●** = connected, computed exactly and fresh on each open: a local
mosh-client is talking to that session's mosh-server UDP port (CPU-jiffie sampling was tried and
abandoned — keepalive work is sub-jiffie). `enter` attach · `ctrl-r` re-summarise · `ctrl-x` kill
· `esc` fresh. Non-interactive: `--list`, `--attach <session>`, `--query <str>`, `--reap`.

`zellij::resume <session>` — the local analogue: stages the attach, de-nests the auto-attach
wrapper (deleting its husk), and execs `zellij attach <session>`.

## Rebuild after a cmux restart / mass disconnect

```bash
python3 scripts/rebuild-durable.py [hosts...] --dry-run   # plan (hosts default: bonbon taffy <local>)
python3 scripts/rebuild-durable.py [hosts...]             # create surfaces + send attaches
python3 scripts/rebuild-durable.py [hosts...] --retry     # re-send to idle surfaces for stragglers
python3 scripts/rebuild-durable.py [hosts...] --retitle   # rename connected tabs to short ids
python3 scripts/rebuild-durable.py [hosts...] --bind      # backfill cmux resume bindings
```

Sorts each live session into a workspace named after its repo (cwd basename), uses the workspace's
initial surface before minting extras, and sends the attach (`ssh::durable --attach` remote,
`zellij::resume` local). Idempotent once settled — connected sessions are skipped (exact mosh-port
check remote; live attach-client process local). Local sessions are resumed only if DETACHED and
MEANINGFUL — a real process in the pane tree (claude, vim, a build), judged like
`zellij::sweep-husks`; screen text lies both ways (dump-screen is blank for detached sessions and
alternate-screen TUIs), so bare wrapper husks are never resumed.

A single pass lands ~60-95%: sends into still-booting surfaces are dropped, and each attach is an
async de-nest + mosh handshake. Run the default pass, `--retry` a couple of times (it reuses idle
surfaces — re-running the default pass mid-settle mints a duplicate surface per straggler), then
`--retitle` (reads the `[mosh]` auto-title, falling back to the zellij status bar via read-screen;
nested and locally-resumed tabs go stale otherwise). Stubborn stragglers:
`ssh::durable <host> --query <name>` / `zellij::resume <session>` by hand. Under load some
surfaces stay nested — a local wrapper with the mosh inside; functional, just a messier Ctrl-O.

## Clean empty surfaces after a rebuild

```bash
python3 scripts/clean-empty-surfaces.py                    # report only (default)
python3 scripts/clean-empty-surfaces.py --close            # close everything classified empty
python3 scripts/clean-empty-surfaces.py --close --keep a,b # …but spare these zellij sessions
```

A rebuild leaves roughly as many junk surfaces as real ones. Three kinds, opposite on screen and
equally empty: **dead husk** (blank screen; its session lives on again on the rebuilt tab), **bare
wrapper** (busy-looking screen — status bar, starship — but the pane tree runs nothing), and
**fresh agent** (a pi/claude that never exchanged tokens: usage line `0% │ ↑0 ↓0 │ $0`; the
startup banner and a minted session UUID are both WRONG signals, and this check runs before the
remote/local split because a remote agent is invisible to the process-tree test). Judge the first
two by process tree, never screen text. Remote mosh tabs and local real work are kept.

Gotchas the script encodes — keep them true when editing it:

- **`--keep` the sessions you just resurrected**: a resurrected skeleton is fresh shells and reads
  as a bare wrapper, so cleanup silently undoes the resurrection.
- Close by UUID from one upfront `cmux tree` snapshot (`surface:N` refs renumber mid-loop); never
  close `$CMUX_SURFACE_ID`; a refused close is stderr + nonzero with EMPTY stdout, so fold stderr
  into the check. A timed-out or hung `cmux tree` must fail loudly — parsed as zero surfaces it
  reads as "no empty surfaces", indistinguishable from success.
- cmux refuses to close a workspace's last surface; on exactly that error the script re-counts and
  closes the workspace instead. The workspace NAME is lost — keep a real surface in ones worth
  naming.

## Resurrect unfinished agent work (judge-and-resume)

A resurrected EXITED skeleton is layout + cwd + scrollback with FRESH shells (`pane_content` is
geometry, not scrollback), so it reads dead even when the attach worked. Don't chase skeletons —
recover the WORK: judge each dead claude/pi conversation from its transcript and resume only the
unfinished ones. Most died at rest on a completed answer.

1. **Inventory the dead.** Serialized pane titles name the work — `✳ <task>` is claude,
   `π - <task> - <repo>` is pi. zellij cannot dump-layout an EXITED session; read the cache
   (macOS `~/Library/Caches/org.Zellij-Contributors.Zellij/contract_version_1/session_info`,
   linux `~/.cache/zellij/contract_version_1/session_info`):

   ```bash
   rg -o '^\s+title "(.*)"' "$CACHE/<session>/session-metadata.kdl"
   ```

   Missing or generic metadata (common remotely): go by the transcript stores directly —
   `~/.claude*/projects/` and `~/.pi*/agent/sessions/<encoded-cwd>/<ts>_<uuid>.jsonl`, excluding
   `*/subagents/*`. pi RENAMES a session as work evolves — scan every `session_info` name record,
   not just the first.
2. **Establish liveness before judging** — a live session's transcript looks identical to a dead
   one's, and resuming one runs it twice. fd-scans are useless (both agents append-and-close).
   What works: statusline uuids (`cmux read-screen` each live tab and regex the uuid out — both
   TUIs print their session id), and pi process etimes (a session file created after every live
   `pi` process started is dead for certain).
3. **Judge from the last turns.** FINISHED = the final assistant text is a completion report with
   nothing outstanding. UNFINISHED = pending tool call, unanswered ask or AskUserQuestion, or
   self-flagged undone items ("Not committed"). Fan the reading out to subagents (a few files
   each, head/tail/jq — never whole transcripts). Traps: **mtime is not activity** (sync and
   bookkeeping records bump it; a batch sharing one mtime to the second is a sync artifact — judge
   by record timestamps); `[subagent]`-named pi sessions and single-prompt one-shots are ephemeral
   workers whose output was already consumed; `/tmp`-cwd claude dirs are batch workers;
   `/clear`-only files are stubs. (`~/.local/bin/resurrect` is claude-transcript-based and blind
   to pi.)
4. **Resume each unfinished session:**

   ```bash
   python3 scripts/resume-agent-session.py --kind pi --id 019ffb15-8130 \
       --slug wall-fixes --workspace sharetrawl --host taffy        # remote
   python3 scripts/resume-agent-session.py --kind claude --id 375fda41 \
       --slug submodule-token --workspace hails.info                # local
   ```

   Local: sends `<kind>::resume <id>` into a fresh surface. Remote: declares the resume in a
   layout (`zsh -ic "<kind>::resume <id> || exec zsh"` — write-chars is silently dropped against
   detached sessions, and `|| exec zsh` keeps a failed resume debuggable) and creates the session
   with `mosh <host> -- zellij --session cmux-<host>-<kind>-<slug> --new-session-with-layout
   <abs-path>`. The script resolves the id fragment against the same stores the resolvers search
   (every `~/.pi*` profile included) and aborts on ambiguity — `pi::resume` fuzzy-matches and
   would `head -1` one of two — and on remote session-name collisions (an existing name, live or
   EXITED skeleton, would be attached instead of running the layout). Booting surfaces eat ~half
   of first sends, so it polls for evidence (the command's echo, the session id on a non-echo
   statusline line, the session existing remotely) and re-sends — up to 3 attempts, only while
   nothing has landed — then retitles the tab `<slug> <short-id>` and exits nonzero unless the id
   was verified on the statusline. Layout-created sessions carry no resume binding (`--bind`
   skips them); the next rebuild pass reconnects them, since connected-detection matches
   `zellij --session` as well as `attach`.

## Move a pi session to another host

pi keys a session to the DIRECTORY it lives in: copy the file into the target's project dir and
rewrite `cwd` in its first `{"type":"session"}` line (historical paths inside tool output are a
record — leave them; the copies then diverge). Check the format loads on the target FIRST — host
pi versions drift — with `pi --export <session-file>` (takes the file as INPUT; loads and exits,
no TTY needed). Then start it with the layout trick above, remembering that `$HOME` in a
`cmux send` expands LOCALLY before mosh runs — remote absolute paths only.

## Restart survival — resume bindings

- **cmux app restart:** zellij servers survive the pty SIGHUP — sessions sit detached with work
  running. Rebuild, or let resume bindings reattach automatically.
- **macOS reboot:** servers die. Session-serialization leaves EXITED skeletons (`zellij attach`
  resurrects layout/cwd/scrollback with fresh shells); recover agent work via judge-and-resume.

Every attach path registers a per-surface restart command (`cmux surface resume set`):
auto-attach.zsh (local wrappers, guarded to empty `$CMUX_REMOTE_TRANSPORT`), `zellij::resume`
(kind `zellij`, `env TMPDIR=/tmp zellij attach <session>`), `ssh::durable::attach` (kind
`zellij-mosh`, `mosh <host> -- zellij attach <session>`). On reopen cmux replays each binding.
Bindings are gated by signed prefix approvals: set the three prefixes above to Auto-Restore in
**Settings → Terminal → Resume Commands** (CLI-set bindings default to manual approval; approval
is UI-only by design). `--bind` backfills tabs attached before registration existed; registration
can miss a surface's first seconds — auto-attach logs `resume-bind set|unchanged|set-FAILED|skip`
to `~/.cache/cmux-zellij/attempts.log`.

## Reap orphaned mosh-servers

`ssh::durable <host> --reap` kills mosh-servers >120s old with no live local client. **Opt-in
only** — the automatic teardown reap was removed after a raced live-client check dropped every
attached tab. Safe: only the transport dies; the session persists and the picker re-moshes.
Caveat: "no local client" is judged from THIS machine — a session attached from another host
looks orphaned here.

## cmux CLI quick ref (current — `cmux rpc` is gone)

`cmux workspace list` · `cmux list-pane-surfaces --workspace <ws>` · `cmux workspace create --name <n>
--cwd <d> --focus false` (spawns an initial surface) · `cmux new-surface --workspace <ws> --focus
false` (prints the new ref) · `cmux send --surface <s> "cmd\n"` (inject a command) · `cmux
rename-tab --surface <s> <title>` · `cmux read-screen --surface <s> --workspace <ws>` · `cmux
close-workspace --workspace <ws>` · `cmux surface resume set|get|show|clear --surface <s>
--workspace <ws>` (restart command metadata; `set --kind <k> --name <n> --shell <cmd>`).
