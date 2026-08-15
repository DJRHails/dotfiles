#!/usr/bin/env python3
"""Resume an unfinished claude/pi session into a cmux tab — local or remote.

The judge-and-resume workflow (SKILL.md "Resurrecting unfinished agent work") ends with a list of
dead-but-unfinished agent sessions. This script performs the resume for one of them:

  local host   send `claude::resume <id>` / `pi::resume <id>` into a fresh surface — the zsh
               helpers (modules/claude/aliases.zsh, modules/pi/aliases.zsh) resolve the transcript,
               cd to its recorded cwd, and route the owning config dir/profile.
  remote host  `zellij action write-chars` is silently dropped against detached sessions, so the
               resume command is declared in a LAYOUT and the session is created around it:
               `mosh <host> -- zellij --session cmux-<host>-<kind>-<slug> --new-session-with-layout
               <remote-path>.kdl`, sent into a fresh surface. The layout pane runs
               `zsh -ic "<kind>::resume <id> || exec zsh"` — the `|| exec zsh` keeps the pane (and
               the session) alive to debug a failed resume instead of insta-exiting.

  python3 resume-agent-session.py --kind pi --id 019ffb15-8130 --slug wall-fixes \
      --workspace sharetrawl [--host taffy] [--cwd /home/d/projects/...] [--dry-run]

Hard-won details this script owns so you don't have to:
  - Sends into a still-booting surface are EATEN silently (about half of first sends in practice).
    It polls for evidence — the sent command's echo, the session id appearing in the tab
    statusline (on a line that is NOT the echo), and remotely the session existing at all — and
    re-sends (up to 3 attempts) only while no evidence has ever appeared, so a slow-but-landed
    send is never re-typed into the now-running agent TUI. Exits nonzero unless the id was
    verified on the statusline.
  - A partial session id that matches two transcripts resumes an arbitrary one (`head -1` in
    `pi::resume`, which fuzzy-matches; a partial claude id simply fails to resolve). The script
    resolves the fragment against the same stores the resolvers search — every `~/.pi*` profile
    included — aborts on ambiguity, and passes the full unique id.
  - A remote session name that already exists (live OR an EXITED skeleton) would be attached or
    resurrected instead of running the layout — it aborts and asks for a different --slug.
  - Layout-created sessions get no cmux resume binding (`--bind` does not cover them); the next
    rebuild pass reconnects them, since REMOTE_CONN matches `zellij --session` invocations.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
import time
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "rebuild_durable", Path(__file__).with_name("rebuild-durable.py"))
_RD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_RD)

UUID_LINE = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
BOOT_WAIT = 9        # surface shell boot before the first send
SEND_ATTEMPTS = 3
POLL_STEP = 4
POLL_WINDOW = 20     # per send-attempt, waiting for evidence the send landed
LOAD_WINDOW = 90     # once landed, waiting for the agent TUI to show the session id

# Must cover everything the resolvers search: claude::resume uses exactly these three roots;
# pi::resume globs every profile ("$HOME"/.pi*/agent/sessions) — searching fewer would let the
# ambiguity check pass while the alias `head -1`s a different profile's file.
CLAUDE_ROOTS = ["~/.claude", "~/.claude-ant", "~/.agents"]
PI_ROOTS = ["~/.pi*/agent/sessions"]


def find_transcripts(host: str, kind: str, fragment: str) -> list[str]:
    roots = CLAUDE_ROOTS if kind == "claude" else PI_ROOTS
    script = (f"find {' '.join(roots)} -name '*{fragment}*.jsonl' "
              "-not -path '*/subagents/*' 2>/dev/null; true")
    if host == _RD.LOCAL_HOST:
        out = _RD.sh(["sh", "-c", script]).stdout
    else:
        out = _RD.ssh_sh(host, script, timeout=30)
    return [ln for ln in out.splitlines() if ln.strip()]


def remote_sessions(host: str) -> list[str]:
    """Session names on the host — distinguishing "none" from "zellij didn't run", because an
    empty answer silently waves the duplicate-session guard through to attach the wrong session."""
    out = _RD.ssh_sh(
        host,
        "command -v zellij >/dev/null 2>&1 || { echo __NO_ZELLIJ__; exit 0; }; "
        "zellij list-sessions -ns 2>/dev/null; true",
        timeout=20)
    if "__NO_ZELLIJ__" in out:
        raise SystemExit(f"zellij is not on PATH in a non-interactive shell on {host} — "
                         "cannot judge session names, refusing to guess")
    return out.split()


def full_session_id(kind: str, transcript: str) -> str:
    stem = Path(transcript).stem
    return stem.split("_", 1)[1] if kind == "pi" and "_" in stem else stem


def ensure_workspace(name: str, cwd: str) -> str:
    ws = _RD.list_ws()
    if name in ws:
        return ws[name]
    out = _RD.cmux("workspace", "create", "--name", name, "--cwd", cwd, "--focus", "false")
    return re.search(r"workspace:\d+", out).group(0)


def evidence(sref: str, wref: str, cmd: str, session_id: str, host: str,
             zj_session: str | None) -> str:
    """'' | 'typed' (the sent command's echo is on screen) | 'landed' (remote session exists) |
    'verified' (id on the tab statusline).

    The echo of the sent command contains the session id locally, so 'verified' must exclude
    echo lines — otherwise a failed `::resume` sitting at a shell error would verify. Transient
    probe failures count as no evidence, not a crash: aborting mid-poll after the send landed
    invites a re-run under a fresh --slug, i.e. resuming the same session twice.
    """
    try:
        screen = _RD.cmux("read-screen", "--surface", sref, "--workspace", wref)
    except RuntimeError:
        screen = ""
    if any(session_id[:18] in ln and "::resume" not in ln for ln in screen.splitlines()):
        return "verified"
    if zj_session:
        try:
            if zj_session in remote_sessions(host):
                return "landed"
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            print(f"remote probe failed ({e.__class__.__name__}) — treating as no evidence yet")
    if cmd[:20] in screen:
        return "typed"
    return ""


def send_until_landed(sref: str, wref: str, cmd: str, session_id: str,
                      host: str, zj_session: str | None) -> str:
    """Send, re-sending ONLY while no evidence has ever appeared — once anything (echo, remote
    session, statusline) shows, a re-send would be typed into the running TUI and submitted as a
    user turn in the very conversation being rescued. Returns the final state."""
    state = ""
    for attempt in range(1, SEND_ATTEMPTS + 1):
        _RD.cmux("send", "--surface", sref, "--workspace", wref, cmd + "\n")
        deadline = time.time() + POLL_WINDOW
        while time.time() < deadline:
            time.sleep(POLL_STEP)
            state = evidence(sref, wref, cmd, session_id, host, zj_session)
            if state:
                break
        if state:
            break
        print(f"send attempt {attempt} showed no evidence — re-sending")
    if not state:
        raise SystemExit(f"send never landed on {sref} after {SEND_ATTEMPTS} attempts — "
                         "check the surface by hand")
    deadline = time.time() + LOAD_WINDOW
    while state != "verified" and time.time() < deadline:
        time.sleep(POLL_STEP)
        state = evidence(sref, wref, cmd, session_id, host, zj_session)
    print(f"{sref}: {state}" + ("" if state == "verified" else
          " (session id never appeared on the statusline — check the tab)"))
    return state


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--host", default=_RD.LOCAL_HOST)
    ap.add_argument("--kind", required=True, choices=["claude", "pi"])
    ap.add_argument("--id", required=True, dest="fragment",
                    help="session id or a uniquely-matching fragment")
    ap.add_argument("--slug", required=True,
                    help="short descriptive name — tab title and remote session suffix")
    ap.add_argument("--workspace", required=True, help="cmux workspace name (usually the repo)")
    ap.add_argument("--cwd", default=None,
                    help="pane cwd for the remote layout (a REMOTE path); defaults to ~")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    local = a.host == _RD.LOCAL_HOST

    # The slug names a remote file, a zellij session and a KDL string; the fragment is spliced
    # into a find pattern. Constrain both before they touch a shell. The slug charset also keeps
    # the session visible to rebuild-durable's cmux-<host>-([A-Za-z0-9-]+) matchers.
    if not re.fullmatch(r"[A-Za-z0-9-]+", a.slug):
        raise SystemExit(f"--slug '{a.slug}' must match [A-Za-z0-9-]+ — it becomes a file name, "
                         "a zellij session name and a KDL string")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", a.fragment):
        raise SystemExit(f"--id '{a.fragment}' has characters unsafe in a find pattern — "
                         "pass a plain id fragment")
    if local and a.cwd:
        raise SystemExit("--cwd only applies to remote resumes; a local resume cds to the "
                         "transcript's recorded cwd")

    matches = find_transcripts(a.host, a.kind, a.fragment)
    if not matches:
        raise SystemExit(f"no {a.kind} transcript on {a.host} matches '*{a.fragment}*.jsonl'")
    if len(matches) > 1:
        listing = "\n  ".join(matches)
        raise SystemExit(f"'{a.fragment}' is ambiguous on {a.host} — pass a longer fragment:"
                         f"\n  {listing}")
    session_id = full_session_id(a.kind, matches[0])
    if not UUID_LINE.fullmatch(session_id):
        raise SystemExit(f"resolved '{session_id}' from {matches[0]} is not a session uuid — "
                         "the match is probably not a transcript; pass a longer --id")
    print(f"transcript: {matches[0]}\nsession id: {session_id}")

    zj_session = None if local else f"cmux-{a.host}-{a.kind}-{a.slug}"
    if not local:
        if zj_session in remote_sessions(a.host):
            raise SystemExit(f"{zj_session} already exists on {a.host} (live or EXITED skeleton) "
                             "— pick another --slug, or attach it instead")
        # Absolute remote paths only: mosh args are not shell-expanded on the remote, and the
        # local shell would eat any $HOME/~ before mosh ever runs (SKILL.md, pi-migration gotchas).
        rhome = _RD.ssh_sh(a.host, 'printf %s "$HOME"', timeout=20).strip()
        layout_path = f"{rhome}/.cache/resume-{a.slug}.kdl"
        layout = ('layout {\n'
                  f'    pane command="zsh" cwd="{a.cwd or rhome}" {{\n'
                  f'        args "-ic" "{a.kind}::resume {session_id} || exec zsh"\n'
                  '    }\n}\n')
        cmd = (f"mosh {a.host} -- zellij --session {zj_session} "
               f"--new-session-with-layout {layout_path}")
    else:
        cmd = f"{a.kind}::resume {session_id}"

    if a.dry_run:
        print(f"--dry-run: workspace {a.workspace}; would send: {cmd}")
        return 0

    if not local:
        done = _RD.sh(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", a.host,
                       f"mkdir -p {rhome}/.cache && cat > {layout_path}"],
                      input=layout, timeout=30)
        if done.returncode:
            raise SystemExit(f"layout write to {a.host}:{layout_path} failed: "
                             f"{done.stderr.strip() or f'ssh exit {done.returncode}'}")
        print(f"layout written: {a.host}:{layout_path}")
    wref = ensure_workspace(a.workspace, _RD.local_repo_dir(a.workspace))
    sref = re.search(r"surface:\d+",
                     _RD.cmux("new-surface", "--workspace", wref, "--focus", "false")).group(0)
    print(f"surface {sref} in {a.workspace} ({wref}); waiting {BOOT_WAIT}s for the shell")
    time.sleep(BOOT_WAIT)
    state = send_until_landed(sref, wref, cmd, session_id, a.host, zj_session)
    _RD.cmux("rename-tab", "--surface", sref, "--workspace", wref,
             f"{a.slug} {session_id[:8]}")
    # 'landed' can be an EXITED skeleton whose resume already died — only a statusline sighting
    # proves the agent is up, so anything less must not read as success to a scripted sweep.
    return 0 if state == "verified" else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (_RD.SSHError, subprocess.TimeoutExpired) as e:
        sys.exit(f"{e.__class__.__name__}: {e} — is --host reachable over ssh?")
