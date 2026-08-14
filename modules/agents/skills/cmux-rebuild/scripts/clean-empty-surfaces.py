#!/usr/bin/env python3
"""Find (and optionally close) cmux surfaces that hold no work, after a durable rebuild.

A rebuild leaves two kinds of junk behind. Both LOOK different on screen but are equally empty:

  dead-husk    the pre-restart surface whose terminal exited — `cmux read-screen` is blank. Its
               resume binding still names the session it used to hold; that session is normally
               live again on the NEW surface the rebuild made, so the husk is a pure duplicate.
  bare-wrapper a LIVE local auto-attach wrapper (`Zellij (cmux-<local>-…)`) sitting at a bare
               shell prompt. Screen text looks busy (status bar, starship, direnv noise) but the
               pane tree runs nothing real.

Judging emptiness by screen text alone gets bare-wrappers wrong, so wrappers are judged the way
rebuild-durable.py and zellij::sweep-husks judge them: by the pane PROCESS TREE. Surfaces holding
a remote (mosh) session, or a local session running real work, are always kept.

  python3 clean-empty-surfaces.py                      # report only (default)
  python3 clean-empty-surfaces.py --close              # close every surface classified empty
  python3 clean-empty-surfaces.py --close --keep a,b   # …but spare these zellij sessions

--keep exists for the session you JUST resurrected: a resurrected EXITED skeleton comes back as
layout + cwd + scrollback with FRESH shells, so it runs no work yet and is indistinguishable from
a bare wrapper by the process-tree test. Spare it explicitly or the cleanup undoes the rebuild.

The caller's own surface ($CMUX_SURFACE_ID) is always skipped — closing it would kill the agent
session doing the cleaning. Closing renumbers short refs (surface:N), so every close is issued by
UUID, resolved up front from a single `cmux tree` snapshot.
"""
from __future__ import annotations

import importlib.util
import os
import re
import subprocess
import sys
import time
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "rebuild_durable", Path(__file__).with_name("rebuild-durable.py")
)
_RD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_RD)

# `cmux tree` times out intermittently once the surface count is high; one retry has been enough.
TREE_ATTEMPTS = 3
TREE_RETRY_WAIT = 15

CLOSE = "--close" in sys.argv
SELF_SURFACE = os.environ.get("CMUX_SURFACE_ID", "")
KEEP = {s for a in sys.argv if a.startswith("--keep=") for s in a[len("--keep="):].split(",") if s}
if "--keep" in sys.argv:
    KEEP |= set(sys.argv[sys.argv.index("--keep") + 1].split(","))

# `cmux tree --all --id-format both` rows, e.g.
#   ├── workspace workspace:13 CD036294-…-C456 "decal"
#   │   ├── surface surface:26 AD03747D-…-4665 [terminal] "decal-62" [selected]
UUID = r"[0-9A-Fa-f-]{36}"
WORKSPACE_ROW = re.compile(
    rf"""
    workspace\s+(?P<ref>workspace:\d+)   # short ref
    \s+(?P<uuid>{UUID})                  # stable id
    \s+"(?P<name>[^"]*)"                 # workspace title
    """,
    re.X,
)
SURFACE_ROW = re.compile(
    rf"""
    surface\s+(?P<ref>surface:\d+)       # short ref
    \s+(?P<uuid>{UUID})                  # stable id
    \s+\[(?P<kind>[^\]]+)\]              # terminal | browser
    \s+"(?P<title>[^"]*)"                # tab title
    """,
    re.X,
)
# zellij's status bar names the attached session: " Zellij (cmux-trifle-2-northern-tapirs)  Tab #1"
STATUS_BAR = re.compile(rf"Zellij \((?P<session>{_RD.SESSION_NAME})\)")
# A freshly-started agent with an EMPTY conversation defeats both other tests: the process tree
# sees a live `pi` (meaningful) and the screen looks busy (not blank). Its usage line gives it away
# — "░░░░░░░░░░ 0% │ ↑0 ↓0 │ $0 │ <uuid>" means no tokens have ever been exchanged, whereas a
# loaded session reads "███░░░░░░░ 31% │ ↑374 ↓134k". The startup banner is NOT usable here: it
# still renders above a restored conversation, and a fresh session does mint a session UUID.
AGENT_USAGE = re.compile(
    r"""
    (?P<context>\d+)\s*%        # context window consumed
    \s*│\s*
    ↑\s*(?P<sent>[\d.]+)(?P<sent_unit>[kmb]?)      # tokens sent
    \s+
    ↓\s*(?P<recv>[\d.]+)(?P<recv_unit>[kmb]?)      # tokens received
    """,
    re.X | re.I,
)
# Fallback when the status bar has scrolled off: the resume binding names the session too, as
# either `env TMPDIR=/tmp zellij attach <s>` (local) or `mosh <host> -- zellij attach <s>` (remote).
BINDING = re.compile(
    rf"""
    (?P<mosh>mosh\s+\S+\s+--\s+)?   # present only for remote bindings
    zellij\s+attach\s+
    (?P<session>{_RD.SESSION_NAME})
    """,
    re.X,
)


def cmux(*args: str) -> str:
    """Run a cmux CLI command, returning stdout (empty string on failure)."""
    return subprocess.run(
        ["cmux", *args], capture_output=True, text=True
    ).stdout.strip()


class TreeSnapshotError(RuntimeError):
    """The surface snapshot could not be read, so emptiness cannot be judged."""


def cmux_tree() -> str:
    """The `cmux tree` snapshot, retried, raising rather than degrading to nothing.

    `cmux tree` is genuinely flaky under a big surface count — it times out on one call and
    succeeds on the next. Routing it through `cmux()` swallowed that: a timed-out snapshot parsed
    to zero surfaces and the run reported "no empty surfaces", which is indistinguishable from a
    clean tree and silently cancels the cleanup. Fail loudly instead; a wrong "nothing to do" is
    worse than an error, because it looks like success.
    """
    for attempt in range(TREE_ATTEMPTS):
        done = subprocess.run(["cmux", "tree", "--all", "--id-format", "both"],
                              capture_output=True, text=True)
        if done.returncode == 0 and SURFACE_ROW.search(done.stdout):
            return done.stdout
        if attempt + 1 < TREE_ATTEMPTS:
            time.sleep(TREE_RETRY_WAIT)
    detail = (done.stderr.strip() or done.stdout.strip() or "no output")[:200]
    raise TreeSnapshotError(
        f"`cmux tree` gave no surfaces after {TREE_ATTEMPTS} attempts: {detail}. "
        "Refusing to report on an unreadable tree — re-run once cmux responds."
    )


def cmux_checked(*args: str) -> tuple[bool, str]:
    """Run a cmux command, returning (ok, message) with stderr folded in.

    Close failures report on stderr with a non-zero exit while stdout stays EMPTY, so a
    stdout-only helper renders a refused close as a silent success. The one that bites here is
    `Error: invalid_state: Cannot close the last surface` — cmux will not close a workspace's only
    surface, so an empty wrapper that is alone in its workspace can never be cleaned by
    close-surface; the workspace itself has to be closed.
    """
    done = subprocess.run(["cmux", *args], capture_output=True, text=True)
    message = (done.stdout.strip() or done.stderr.strip()).splitlines()
    return done.returncode == 0, (message[0] if message else "")


def is_last_surface_refusal(message: str) -> bool:
    """True when a close was refused only because the surface is its workspace's last one."""
    return "last surface" in message.lower()


def close_workspace_holding(surface: dict) -> tuple[bool, str]:
    """Close the workspace whose ONLY surface is this empty one.

    Re-counts live surfaces first: the refusal proves the workspace had one surface when the close
    was attempted, but a rebuild pass running alongside can add one, and closing the workspace then
    would take real work with it.
    """
    workspace = surface["ws"]
    siblings = [s for s in surfaces() if s["ws"]["uuid"] == workspace["uuid"]]
    if len(siblings) != 1:
        return False, f"workspace now has {len(siblings)} surfaces — left alone"
    return cmux_checked("workspace", "close", "--workspace", workspace["uuid"])


def surfaces() -> list[dict]:
    """Every terminal surface in the tree, tagged with its workspace."""
    tree = cmux_tree()
    rows, workspace = [], {"ref": "?", "uuid": "", "name": "?"}
    for line in tree.splitlines():
        if m := WORKSPACE_ROW.search(line):
            workspace = m.groupdict()
        if m := SURFACE_ROW.search(line):
            rows.append({**m.groupdict(), "ws": workspace})
    return rows


def classify(surface: dict, meaningful: set[str]) -> tuple[str, str]:
    """Return (verdict, detail) for one surface. Verdict 'empty-*' means safe to close."""
    if surface["uuid"].upper() == SELF_SURFACE.upper():
        return "self", "caller surface"
    if surface["kind"] != "terminal":
        return "keep", surface["kind"]

    ref, ws = surface["uuid"], surface["ws"]["uuid"]
    screen = cmux("read-screen", "--surface", ref, "--workspace", ws)
    raw = cmux("surface", "resume", "get", "--surface", ref, "--workspace", ws)
    binding = " ".join(raw.split())

    if not screen.strip():
        # Re-read: a single blank read can be a transient repaint, not a dead terminal.
        time.sleep(0.3)
        if not cmux("read-screen", "--surface", ref, "--workspace", ws).strip():
            return "empty-dead-husk", binding or "(no binding)"

    session, remote = None, False
    if m := STATUS_BAR.search(screen):
        session = m.group("session")
    elif m := BINDING.search(binding):
        session, remote = m.group("session"), bool(m.group("mosh"))
    if session is None:
        # No zellij at all — a plain shell surface. Empty unless something is on screen.
        busy = len(screen.splitlines()) > 3
        return ("keep", "plain shell") if busy else ("empty-idle-shell", "plain shell")

    if session in KEEP:
        return "keep", f"{session} (--keep)"
    # Checked before the remote/local split: a fresh agent is equally empty on either host, and a
    # remote one is invisible to the local process-tree test.
    if m := AGENT_USAGE.search(screen):
        unused = (
            m.group("context") == "0"
            and m.group("sent") == "0" and not m.group("sent_unit")
            and m.group("recv") == "0" and not m.group("recv_unit")
        )
        if unused:
            return "empty-fresh-agent", f"{session} (agent started, 0 tokens)"
        return "keep", f"{session} (agent, {m.group('context')}% context)"
    if remote or not session.startswith(f"cmux-{_RD.LOCAL_HOST}-"):
        return "keep", session
    return ("keep", session) if session in meaningful else ("empty-bare-wrapper", session)


def main() -> int:
    meaningful = _RD.local_meaningful()
    empty = []
    for surface in surfaces():
        verdict, detail = classify(surface, meaningful)
        title, name = surface["title"][:30], surface["ws"]["name"][:26]
        print(f"{surface['ref']:12} {name:26.26} {title:30.30} {verdict:19} {detail[:60]}")
        if verdict.startswith("empty-"):
            empty.append(surface)

    if not empty:
        print("\nno empty surfaces")
        return 0
    if not CLOSE:
        print(f"\n{len(empty)} empty surfaces — re-run with --close to close them")
        return 0

    closed, dropped, failed = 0, [], []
    for surface in empty:
        ok, message = cmux_checked("close-surface", "--surface", surface["uuid"],
                                   "--workspace", surface["ws"]["uuid"])
        if ok:
            closed += 1
            print(f"closed  {surface['ref']:12} {surface['title'][:30]:30.30} {message}")
            continue
        if not is_last_surface_refusal(message):
            failed.append((surface, message))
            print(f"FAILED  {surface['ref']:12} {surface['title'][:30]:30.30} {message}")
            continue
        # The surface is empty AND alone, so the workspace holds nothing but its own name.
        ok, message = close_workspace_holding(surface)
        label = "dropped" if ok else "FAILED "
        print(f"{label} workspace   {surface['ws']['name'][:30]:30.30} {message}")
        (dropped if ok else failed).append((surface, message))

    print(f"\nclosed {closed} empty surfaces, dropped {len(dropped)} empty workspaces")
    for surface, message in failed:
        print(f"  unresolved: {surface['ref']} in {surface['ws']['name']} — {message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
