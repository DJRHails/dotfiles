#!/usr/bin/env python3
"""Rebuild cmux workspaces for a remote host's live durable (mosh+zellij) sessions, using the
CURRENT cmux CLI. The old ~/.config/cmux/snapshots/sort_bonbon.py used the removed `cmux rpc`
interface and a `wrap-<session>` nesting convention that predates today's de-nesting `ssh::durable`.

For each live remote zellij session: ensure a cmux workspace named after its repo (the cwd
basename), create a surface in it, and `cmux send` the durable attach (`ssh::durable <host>
--attach <session>`) which de-nests + moshes in. Idempotent: sessions already connected (a local
mosh-client is talking to their port) are skipped, so it's safe to re-run.

  python3 rebuild-durable.py [host] --dry-run   # plan only (host defaults to $DURABLE_HOST / bonbon)
  python3 rebuild-durable.py [host]             # create surfaces + connect
  python3 rebuild-durable.py [host] --retry     # re-send to idle surfaces for stragglers (no new ones)
  python3 rebuild-durable.py [host] --retitle   # rename every connected tab to its short session id

Connecting many sessions at once is racy (each attach is an async de-nest + mosh handshake): expect
to run the default pass once, then --retry a couple times, then --retitle. See the skill's SKILL.md.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path

HOST = os.environ.get("DURABLE_HOST") or next((a for a in sys.argv[1:] if not a.startswith("-")), "bonbon")
DRY = "--dry-run" in sys.argv
PROJECTS = Path.home() / "projects"
NAME_OVERRIDES = {"one-billion": "$1bn", "d": "home"}  # repo basename -> workspace name

# session \t cwd, for every live (non-EXITED) remote session
REMOTE_LIST = (
    r"""for s in $(zellij list-sessions 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' """
    r"""| grep -v EXITED | awk '{print $1}'); do """
    r"""c=$(zellij -s "$s" action dump-layout 2>/dev/null """
    r"""| sed -nE 's/^[[:space:]]*cwd "(.*)"$/\1/p' | head -1); printf '%s\t%s\n' "$s" "$c"; done"""
)
# given LP (local mosh-client ports), print the remote session bound to each port that has a client
REMOTE_CONN = (
    r"""lp=" $LP "; ss -uanp 2>/dev/null | awk '/mosh-server/{p="";"""
    r"""for(i=1;i<=NF;i++)if($i ~ /:[0-9]+$/){n=split($i,a,":");p=a[n]} """
    r"""if(match($0,/pid=[0-9]+/))pid=substr($0,RSTART+4,RLENGTH-4); if(p!="")print p,pid}' """
    r"""| while read -r pp pid; do case "$lp" in *" $pp "*) pgrep -af mosh-server """
    r"""| sed -nE "s/^$pid .*zellij attach (-c )?(cmux-[A-Za-z0-9_-]+).*/\2/p";; esac; done"""
)


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def cmux(*a: str) -> str:
    r = sh(["cmux", *a])
    if r.returncode:
        raise RuntimeError(f"cmux {' '.join(a)}: {r.stderr.strip()}")
    return r.stdout.strip()


def ssh_sh(script: str, timeout: int) -> str:
    r = sh(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", HOST, "sh"],
           input=script, timeout=timeout)
    return r.stdout


def live_sessions() -> dict[str, str]:
    out = {}
    for ln in ssh_sh(REMOTE_LIST, 120).splitlines():
        if "\t" in ln:
            s, _, c = ln.partition("\t")
            if c.strip():
                out[s.strip()] = c.strip()
    return out


def local_ports() -> str:
    ports = set()
    for ln in sh(["ps", "-axww", "-o", "command="]).stdout.splitlines():
        toks = ln.split()
        if toks and toks[0].endswith("mosh-client") and HOST in ln:
            ports.add(toks[-1])
    return " ".join(sorted(ports))


def connected() -> set[str]:
    """Sessions a local mosh-client is talking to right now — exact, no CPU-activity guessing."""
    lp = local_ports()
    if not lp.strip():
        return set()
    out = ssh_sh(REMOTE_CONN.replace("$LP", lp), 30)
    return {ln.strip() for ln in out.splitlines() if ln.strip()}


def repo(cwd: str) -> str:
    base = cwd.rstrip("/").split("/")[-1]
    return NAME_OVERRIDES.get(base, base)


def local_repo_dir(name: str) -> str:
    for cand in PROJECTS.glob(f"*/*/{name}"):
        if cand.is_dir():
            return str(cand)
    return str(Path.home())


def list_ws() -> dict[str, str]:
    res = {}
    for ln in sh(["cmux", "list-workspaces"]).stdout.splitlines():
        m = re.search(r"workspace:\d+", ln)
        if not m:
            continue
        name = ln[m.end():].replace("[selected]", "").replace("[focused]", "").strip()
        name = name.lstrip("↺").strip()
        res[name] = m.group(0)
    return res


def retry() -> int:
    """Re-send the attach to idle surfaces (title still 'cmux-trifle-*' or the bare repo name) for
    sessions that didn't connect on the first pass — reuses existing surfaces, never creates new
    ones, so it's safe to run repeatedly."""
    sessions = live_sessions()
    conn = connected()
    byrepo: dict[str, list[str]] = {}
    for s, cwd in sorted(sessions.items()):
        if s not in conn:
            byrepo.setdefault(repo(cwd), []).append(s)
    ws = list_ws()
    sent = 0
    for rp, sess_list in sorted(byrepo.items()):
        wref = ws.get(rp)
        if not wref:
            print(f"  {rp}: no workspace — {len(sess_list)} unplaced")
            continue
        idle = []
        for ln in sh(["cmux", "list-pane-surfaces", "--workspace", wref]).stdout.splitlines():
            m = re.search(r"surface:\d+", ln)
            if not m:
                continue
            title = ln[m.end():].replace("[selected]", "").strip()
            if title.startswith("cmux-trifle-") or title == rp or title == "":
                idle.append(m.group(0))
        for s, sref in zip(sess_list, idle):
            cmux("send", "--surface", sref, "--workspace", wref, f"ssh::durable {HOST} --attach {s}\n")
            sent += 1
            time.sleep(0.4)
        if len(sess_list) > len(idle):
            print(f"  {rp}: {len(sess_list) - len(idle)} sessions had no idle surface")
    print(f"retry: re-sent {sent} attaches")
    return 0


def retitle() -> int:
    """Rename every connected durable tab to its short session id (cmux-<host>-<id> -> <id>). The id
    comes from the surface's '[mosh] cmux-<host>-<id>' auto-title when it de-nested, else from the
    remote zellij status bar ('Zellij (cmux-<host>-<id>)') read off the screen for the nested ones.
    Idle/local surfaces (no remote session anywhere) are left alone."""
    pat = re.compile(rf"cmux-{re.escape(HOST)}-([A-Za-z0-9-]+)")
    barpat = re.compile(rf"Zellij \(cmux-{re.escape(HOST)}-([A-Za-z0-9-]+)\)")
    n = 0
    for wl in sh(["cmux", "list-workspaces"]).stdout.splitlines():
        wm = re.search(r"workspace:\d+", wl)
        if not wm:
            continue
        wref = wm.group(0)
        for ln in sh(["cmux", "list-pane-surfaces", "--workspace", wref]).stdout.splitlines():
            sm = re.search(r"surface:\d+", ln)
            if not sm:
                continue
            sid = pat.search(ln)
            if not sid:  # nested (title is the local wrapper) — read the remote zellij status bar
                scr = sh(["cmux", "read-screen", "--surface", sm.group(0), "--workspace", wref]).stdout
                sid = barpat.search(scr)
            if sid:
                cmux("rename-tab", "--surface", sm.group(0), "--workspace", wref, sid.group(1))
                n += 1
    print(f"retitled {n} connected durable tabs to their short session id")
    return 0


def main() -> int:
    if "--retitle" in sys.argv:
        return retitle()
    if "--retry" in sys.argv:
        return retry()
    sessions = live_sessions()
    conn = connected()
    byrepo: dict[str, list[str]] = {}
    for s, cwd in sorted(sessions.items()):
        byrepo.setdefault(repo(cwd), []).append(s)

    todo = []
    print(f"{HOST}: {len(sessions)} live sessions, {len(conn)} already connected — plan:")
    for rp in sorted(byrepo):
        for s in byrepo[rp]:
            skip = s in conn
            print(f"  {rp:<18} {s:<40} {'skip (connected)' if skip else 'CONNECT'}")
            if not skip:
                todo.append((rp, s))
    if DRY:
        print(f"\n--dry-run: would connect {len(todo)}.")
        return 0

    wraps = [w for w in sh(["zellij", "list-sessions", "-ns"]).stdout.split() if w.startswith("wrap-")]
    print(f"\ndeleting {len(wraps)} orphaned wrap- stubs")
    for w in wraps:
        sh(["zellij", "delete-session", "--force", w])

    ws = list_ws()
    pairs = []  # (surface_ref, workspace_ref, session)
    for rp, s in todo:
        if rp not in ws:
            ws[rp] = re.search(r"workspace:\d+", cmux(
                "workspace", "create", "--name", rp, "--cwd", local_repo_dir(rp), "--focus", "false")).group(0)
        sref = re.search(r"surface:\d+", cmux("new-surface", "--workspace", ws[rp], "--focus", "false")).group(0)
        pairs.append((sref, ws[rp], s))
    print(f"created {len(pairs)} surfaces across {len({w for _, w, _ in pairs})} workspaces; settling…")
    time.sleep(6)

    for sref, wref, s in pairs:
        cmux("send", "--surface", sref, "--workspace", wref, f"ssh::durable {HOST} --attach {s}\n")
        time.sleep(0.3)
    print(f"sent {len(pairs)} durable attaches — mosh handshakes complete asynchronously; "
          "run --retry for stragglers, then --retitle")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
