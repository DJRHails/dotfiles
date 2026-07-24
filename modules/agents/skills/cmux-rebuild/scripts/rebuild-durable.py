#!/usr/bin/env python3
"""Rebuild cmux workspaces for live durable zellij sessions — remote (mosh) and local — using the
CURRENT cmux CLI. The old ~/.config/cmux/snapshots/sort_bonbon.py used the removed `cmux rpc`
interface and a `wrap-<session>` nesting convention that predates today's de-nesting `ssh::durable`.

Remote hosts (bonbon, taffy, …): for each live remote zellij session, ensure a cmux workspace named
after its repo (the cwd basename), create a surface in it, and `cmux send` the durable attach
(`ssh::durable <host> --attach <session>`) which de-nests + moshes in. Sessions already connected
(a local mosh-client is talking to their port) are skipped.

The local host (the machine cmux runs on, e.g. trifle): its own zellij sessions need no mosh —
after a cmux restart they sit detached with their work still running. Sessions that are DETACHED
(no `zellij attach` client) and MEANINGFUL (a real foreground process in the pane tree — claude,
vim, a build — judged like zellij::sweep-husks) are resumed the same way, sending
`zellij::resume <session>` (modules/zellij/mosh-zellij.zsh) which de-nests the auto-attach wrapper
and attaches the old session. Bare wrapper husks are never resumed.

  python3 rebuild-durable.py [hosts...] --dry-run   # plan only (default hosts: bonbon taffy <local>)
  python3 rebuild-durable.py [hosts...]             # create surfaces + connect
  python3 rebuild-durable.py [hosts...] --retry     # re-send to idle surfaces for stragglers
  python3 rebuild-durable.py [hosts...] --retitle   # rename connected tabs to short session ids
  python3 rebuild-durable.py [hosts...] --bind      # backfill cmux resume bindings on connected tabs

Connecting many sessions at once is racy (each remote attach is an async de-nest + mosh handshake):
expect to run the default pass once, then --retry a couple times, then --retitle. See SKILL.md.
"""
from __future__ import annotations

import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

LOCAL_HOST = socket.gethostname().split(".")[0].lower()
_ARG_HOSTS = [a for a in sys.argv[1:] if not a.startswith("-")]
HOSTS = _ARG_HOSTS or ([os.environ["DURABLE_HOST"]] if os.environ.get("DURABLE_HOST")
                       else ["bonbon", "taffy", LOCAL_HOST])
DRY = "--dry-run" in sys.argv
MODE_FLAGS = {"--retry", "--retitle", "--bind"}
PROJECTS = Path.home() / "projects"
NAME_OVERRIDES = {"one-billion": "$1bn", "d": "home", "dh": "home"}  # cwd basename -> workspace

ANSI = re.compile(r"\x1b\[[0-9;]*m")
SESSION_NAME = r"cmux-[A-Za-z0-9_-]+"

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

# Pane processes that do NOT make a session meaningful (zellij::sweep-husks' filter): zellij
# itself, bare shells, and the transient helpers a prompt snapshot spawns.
HUSK_NOISE = re.compile(
    r"""(?x)
      ^ (?: /[^\ ]*/ )? zellij (?: \s | $ )                                   # zellij client/server
    | ^ (?: /usr/bin/ | /bin/ )? -? (?: zsh | bash | sh | login ) (?: \s | $ )  # bare shells
    | snapshot-zsh .* eval                                                    # prompt snapshot
    | ^ (?: /[^\ ]*/ )? (?: ps | awk | sed | grep | head | caffeinate ) (?: \s | $ )  # transient helpers
    """
)


# zellij's socket dir follows TMPDIR; cmux surface shells default to /var/folders/… on macOS
# while auto-attach.zsh creates every session under /tmp — force the match or local zellij
# calls silently see zero sessions.
ZELLIJ_ENV = {**os.environ, "TMPDIR": "/tmp"}


def is_local(host: str) -> bool:
    return host == LOCAL_HOST


def sh(cmd, **kw):
    if cmd and cmd[0] == "zellij":
        kw.setdefault("env", ZELLIJ_ENV)
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def cmux(*a: str) -> str:
    r = sh(["cmux", *a])
    if r.returncode:
        raise RuntimeError(f"cmux {' '.join(a)}: {r.stderr.strip()}")
    return r.stdout.strip()


class SSHError(RuntimeError):
    """The ssh transport itself failed (unreachable host, timeout, auth) — distinct from a
    successful connection that legitimately lists zero sessions."""


def ssh_sh(host: str, script: str, timeout: int) -> str:
    r = sh(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host, "sh"],
           input=script, timeout=timeout)
    if r.returncode:
        raise SSHError(r.stderr.strip() or f"ssh exit {r.returncode}")
    return r.stdout


def attach_cmd(host: str, session: str) -> str:
    """The command typed into a surface to bind it to a session: mosh hop for remote hosts,
    plain local resume (same de-nest handoff) for the cmux host's own sessions."""
    if is_local(host):
        return f"zellij::resume {session}\n"
    return f"ssh::durable {host} --attach {session}\n"


def local_live() -> list[str]:
    out = []
    for ln in sh(["zellij", "list-sessions"], timeout=20).stdout.splitlines():
        ln = ANSI.sub("", ln).strip()
        if ln and "EXITED" not in ln:
            out.append(ln.split()[0])
    return out


def local_connected() -> set[str]:
    """Sessions with a live `zellij attach` client — i.e. already shown in some surface."""
    out = set()
    for ln in sh(["ps", "-axww", "-o", "command="]).stdout.splitlines():
        m = re.search(rf"zellij attach (?:-c )?({SESSION_NAME})", ln)
        if m:
            out.add(m.group(1))
    return out


def local_meaningful() -> set[str]:
    """Local sessions whose pane tree runs a real foreground process (claude, vim, mosh, a
    build, …) — the complement of zellij::sweep-husks' idle set. Judged by processes, not screen
    text: dump-screen is blank for detached sessions and alternate-screen TUIs."""
    procs: dict[str, tuple[str, str]] = {}  # pid -> (ppid, command)
    for ln in sh(["ps", "-axww", "-o", "pid=,ppid=,command="]).stdout.splitlines():
        parts = ln.split(None, 2)
        if len(parts) == 3 and parts[0].isdigit():
            procs[parts[0]] = (parts[1], parts[2])
    kids: dict[str, list[str]] = {}
    for pid, (ppid, _) in procs.items():
        kids.setdefault(ppid, []).append(pid)
    out = set()
    for pid, (_, cmd) in procs.items():
        m = re.search(rf"zellij --server .*/({SESSION_NAME})$", cmd)
        if not m:
            continue
        stack = list(kids.get(pid, []))
        while stack:
            child = stack.pop()
            if not HUSK_NOISE.search(procs[child][1]):
                out.add(m.group(1))
                break
            stack.extend(kids.get(child, []))
    return out


def local_cwd(session: str) -> str:
    try:
        r = sh(["zellij", "-s", session, "action", "dump-layout"], timeout=15)
    except subprocess.TimeoutExpired:
        return ""
    for ln in r.stdout.splitlines():
        m = re.match(r'\s*cwd "(.*)"$', ln)
        if m:
            return m.group(1)
    return ""


def live_sessions(host: str) -> dict[str, str]:
    out = {}
    for ln in ssh_sh(host, REMOTE_LIST, 120).splitlines():
        if "\t" in ln:
            s, _, c = ln.partition("\t")
            if c.strip():
                out[s.strip()] = c.strip()
    return out


def local_ports(host: str) -> str:
    ports = set()
    for ln in sh(["ps", "-axww", "-o", "command="]).stdout.splitlines():
        toks = ln.split()
        if toks and toks[0].endswith("mosh-client") and host in ln:
            ports.add(toks[-1])
    return " ".join(sorted(ports))


def connected(host: str) -> set[str]:
    """Sessions a local mosh-client is talking to right now — exact, no CPU-activity guessing."""
    lp = local_ports(host)
    if not lp.strip():
        return set()
    out = ssh_sh(host, REMOTE_CONN.replace("$LP", lp), 30)
    return {ln.strip() for ln in out.splitlines() if ln.strip()}


def survey(host: str) -> list[tuple[str, str, str, str]]:
    """(host, repo, session, status) for the host's live sessions; status is 'connect',
    'connected', or 'husk'. Local husks/connected skip the cwd lookup (repo '-')."""
    rows = []
    if is_local(host):
        conn, meaningful = local_connected(), local_meaningful()
        for s in sorted(local_live()):
            if s in conn:
                rows.append((host, "-", s, "connected"))
            elif s not in meaningful:
                rows.append((host, "-", s, "husk"))
            else:
                rows.append((host, repo(local_cwd(s) or str(Path.home())), s, "connect"))
        return rows
    sessions, conn = live_sessions(host), connected(host)
    for s, cwd in sorted(sessions.items()):
        rows.append((host, repo(cwd), s, "connected" if s in conn else "connect"))
    return rows


def survey_hosts(hosts: list[str]) -> tuple[list[tuple[str, str, str, str]], set[str]]:
    """Rows for every reachable host, plus the set of hosts skipped due to a transport failure —
    callers must not treat a skipped host as having zero sessions."""
    rows, skipped = [], set()
    for host in hosts:
        try:
            rows += survey(host)
        except (subprocess.TimeoutExpired, OSError, SSHError) as e:
            print(f"{host}: SKIPPED ({e.__class__.__name__}: {e})")
            skipped.add(host)
    return rows, skipped


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
    for ln in cmux("list-workspaces").splitlines():
        m = re.search(r"workspace:\d+", ln)
        if not m:
            continue
        name = ln[m.end():].replace("[selected]", "").replace("[focused]", "").strip()
        name = name.lstrip("↺").strip()
        res[name] = m.group(0)
    return res


def idle_surfaces(wref: str, repo_name: str, husks: set[str]) -> list[str]:
    """Surfaces in a workspace that are safe to send an attach into: untouched fresh surfaces
    (title empty or the repo name) and auto-attach wrappers whose session is a bare husk. A
    `cmux-<local>-*` title whose session holds real work is a RESUMED local tab — never reuse it."""
    idle = []
    for ln in cmux("list-pane-surfaces", "--workspace", wref).splitlines():
        m = re.search(r"surface:\d+", ln)
        if not m:
            continue
        title = ln[m.end():].replace("[selected]", "").strip()
        if title in ("", repo_name):
            idle.append(m.group(0))
        elif title.startswith(f"cmux-{LOCAL_HOST}-") and title in husks:
            idle.append(m.group(0))
    return idle


def retry(hosts: list[str]) -> int:
    """Re-send attaches to idle surfaces for sessions that didn't connect on the first pass —
    reuses existing surfaces, never creates new ones, so it's safe to run repeatedly."""
    rows, skipped = survey_hosts(hosts)
    if skipped:
        print(f"retry: skipping unreachable hosts: {', '.join(sorted(skipped))}")
    pending = [r for r in rows if r[3] == "connect"]
    byrepo: dict[str, list[tuple[str, str]]] = {}
    for host, rp, s, _ in pending:
        byrepo.setdefault(rp, []).append((host, s))
    ws = list_ws()
    husks = set(local_live()) - local_meaningful()
    sent = 0
    for rp, items in sorted(byrepo.items()):
        wref = ws.get(rp)
        if not wref:
            print(f"  {rp}: no workspace — {len(items)} unplaced")
            continue
        idle = idle_surfaces(wref, rp, husks)
        for (host, s), sref in zip(items, idle):
            cmux("send", "--surface", sref, "--workspace", wref, attach_cmd(host, s))
            sent += 1
            time.sleep(0.4)
        if len(items) > len(idle):
            print(f"  {rp}: {len(items) - len(idle)} sessions had no idle surface")
    print(f"retry: re-sent {sent} attaches")
    return 0


def resolve_surfaces(hosts: list[str]) -> list[tuple[str, str, str, str]]:
    """(workspace_ref, surface_ref, host, short_id) for every surface hosting a durable session.
    The id comes from the surface's 'cmux-<host>-<id>' auto-title (mosh prefixes '[mosh] '), else
    from the zellij status bar ('Zellij (cmux-<host>-<id>)') read off the screen — needed for
    nested surfaces and locally-resumed ones (their tab title goes stale at the deleted wrapper's
    name). Local-host matches only count when their session holds real work, so an idle wrapper
    husk (or a mid-hop title) is never mistaken for a hosted session — retry() keys idle
    detection off those husk titles."""
    pats = [(h, re.compile(rf"cmux-{re.escape(h)}-([A-Za-z0-9-]+)")) for h in hosts]
    barpats = [(h, re.compile(rf"Zellij \(cmux-{re.escape(h)}-([A-Za-z0-9-]+)\)")) for h in hosts]
    meaningful = local_meaningful() if any(is_local(h) for h in hosts) else set()

    def credible(h: str, m: re.Match | None) -> re.Match | None:
        if m and is_local(h) and f"cmux-{h}-{m.group(1)}" not in meaningful:
            return None
        return m

    out = []
    for wl in cmux("list-workspaces").splitlines():
        wm = re.search(r"workspace:\d+", wl)
        if not wm:
            continue
        wref = wm.group(0)
        for ln in cmux("list-pane-surfaces", "--workspace", wref).splitlines():
            sm = re.search(r"surface:\d+", ln)
            if not sm:
                continue
            hit = next(((h, m) for h, pat in pats if (m := credible(h, pat.search(ln)))), None)
            if not hit:
                scr = sh(["cmux", "read-screen", "--surface", sm.group(0), "--workspace", wref]).stdout
                hit = next(((h, m) for h, bp in barpats if (m := credible(h, bp.search(scr)))), None)
            if hit:
                out.append((wref, sm.group(0), hit[0], hit[1].group(1)))
    return out


def retitle(hosts: list[str]) -> int:
    """Rename every connected durable tab to its short session id (cmux-<host>-<id> -> <id>)."""
    n = 0
    for wref, sref, _host, sid in resolve_surfaces(hosts):
        cmux("rename-tab", "--surface", sref, "--workspace", wref, sid)
        n += 1
    print(f"retitled {n} connected durable tabs to their short session id")
    return 0


def bind(hosts: list[str]) -> int:
    """Backfill each connected durable tab's cmux resume binding so an app restart reattaches the
    same session in place (Settings → Terminal → Resume Commands governs auto/ask/manual). The
    attach paths (auto-attach.zsh, zellij::resume, ssh::durable::attach) register these themselves
    going forward; this covers surfaces attached before that existed. Matching bindings are
    skipped so approved ones aren't re-proposed."""
    n = 0
    for wref, sref, host, sid in resolve_surfaces(hosts):
        session = f"cmux-{host}-{sid}"
        if is_local(host):
            kind, command = "zellij", f"env TMPDIR=/tmp zellij attach {session}"
        else:
            kind, command = "zellij-mosh", f"mosh {host} -- zellij attach {session}"
        have = sh(["cmux", "surface", "resume", "get", "--json",
                   "--surface", sref, "--workspace", wref]).stdout
        if command in have:
            continue
        cmux("surface", "resume", "set", "--surface", sref, "--workspace", wref,
             "--kind", kind, "--name", session, "--shell", command)
        n += 1
    print(f"bound {n} durable tabs to resume commands (approve the prefixes as Auto-Restore "
          "in Settings → Terminal → Resume Commands)")
    return 0


def main() -> int:
    # Reject mistyped flags up front — the non-dry default pass mutates the live cmux layout,
    # so a typo'd --dry-run must not silently fall through to it.
    unknown = [a for a in sys.argv[1:] if a.startswith("-") and a not in MODE_FLAGS | {"--dry-run"}]
    if unknown:
        sys.exit(f"unknown flag(s): {' '.join(unknown)} — known: --dry-run {' '.join(sorted(MODE_FLAGS))}")
    if DRY and MODE_FLAGS & set(sys.argv):
        sys.exit("--dry-run only applies to the default pass; --retry/--retitle/--bind run live")
    if "--retitle" in sys.argv:
        return retitle(HOSTS)
    if "--bind" in sys.argv:
        return bind(HOSTS)
    if "--retry" in sys.argv:
        return retry(HOSTS)

    rows, skipped = survey_hosts(HOSTS)
    todo = []  # (host, repo, session)
    for host in HOSTS:
        if host in skipped:
            continue
        hrows = [r for r in rows if r[0] == host]
        n_conn = sum(1 for r in hrows if r[3] == "connected")
        print(f"{host}: {len(hrows)} live sessions, {n_conn} already connected — plan:")
        for _, rp, s, status in hrows:
            label = {"connected": "skip (connected)", "husk": "skip (husk)"}.get(status, "CONNECT")
            print(f"  {rp:<18} {s:<40} {label}")
            if status == "connect":
                todo.append((host, rp, s))
    if DRY:
        print(f"\n--dry-run: would connect {len(todo)}.")
        return 0

    wraps = [w for w in sh(["zellij", "list-sessions", "-ns"]).stdout.split() if w.startswith("wrap-")]
    print(f"\ndeleting {len(wraps)} orphaned wrap- stubs")
    for w in wraps:
        sh(["zellij", "delete-session", "--force", w])

    ws = list_ws()
    spare: dict[str, list[str]] = {}  # workspace_ref -> unused default surfaces from `create`
    pairs = []  # (surface_ref, workspace_ref, host, session)
    for host, rp, s in todo:
        if rp not in ws:
            ws[rp] = re.search(r"workspace:\d+", cmux(
                "workspace", "create", "--name", rp, "--cwd", local_repo_dir(rp), "--focus", "false")).group(0)
            # `workspace create` spawns an initial surface — use it before minting extras,
            # otherwise every fresh workspace strands one idle wrapper surface.
            spare[ws[rp]] = re.findall(
                r"surface:\d+", cmux("list-pane-surfaces", "--workspace", ws[rp]))
        if spare.get(ws[rp]):
            sref = spare[ws[rp]].pop(0)
        else:
            sref = re.search(r"surface:\d+",
                             cmux("new-surface", "--workspace", ws[rp], "--focus", "false")).group(0)
        pairs.append((sref, ws[rp], host, s))
    print(f"created {len(pairs)} surfaces across {len({w for _, w, _, _ in pairs})} workspaces; settling…")
    time.sleep(6)

    for sref, wref, host, s in pairs:
        cmux("send", "--surface", sref, "--workspace", wref, attach_cmd(host, s))
        time.sleep(0.3)
    print(f"sent {len(pairs)} attaches — remote mosh handshakes complete asynchronously; "
          "run --retry for stragglers, then --retitle")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
