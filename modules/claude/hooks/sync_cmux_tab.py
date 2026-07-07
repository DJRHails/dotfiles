#!/usr/bin/env python3
"""Keep cmux tab titles in step with Claude session names (set by /rename).

Two modes, one implementation:

  hook mode (default)   Claude Code hook on UserPromptSubmit + Stop: reads the
                        hook JSON on stdin, syncs this session's tab. stdout
                        stays silent (UserPromptSubmit stdout is injected into
                        the model's context).
  --sweep               Reconcile EVERY live named session on this box (via
                        ~/.claude*/sessions/*.json + /proc/<pid>/environ), run
                        from a systemd user timer. This is what makes renames
                        land regardless of turn state: /rename fires no hook,
                        Stop skips interrupted turns, and messages typed while
                        a turn is running fire no UserPromptSubmit — the sweep
                        catches all of those within a minute.

Why not bash: the previous implementation was bash+awk+jq+ssh string surgery
across three failure investigations; this is the same logic with real parsing,
one log line per action, and a --self-test.

Resolution (remote box, e.g. bonbon): cmux `top` exposes the UI-host-side pid
per surface, and the mosh-client command line carries the exact zellij session
name ("… mosh-client -# bonbon -- zellij attach <name> | …") — match the
session's $ZELLIJ_SESSION_NAME → pid → surface ref → UUID via `tree`. A window
whose zellij session has no UI-host process (mosh disconnected / detached) is
correctly unrenamable: logged `zellij-session-not-found`, fixed by the next
sweep after reattach. On the UI host itself, $CMUX_SURFACE_ID is fresh and
used directly.

In-sync rule (also the fork rule): a terminal tab already titled with the
session name — exactly, or as a "fork: <name>"-style suffix behind a non-name
character — needs nothing. Boundary-anchored, never raw substring, so renaming
"x-2" back to "x" is not fooled by the old title.

Rename goes through the `tab.action` JSON-RPC (`rename-tab` is broken on
current cmux builds) and the acted-on surface is verified, since tab.action
silently falls back to the focused surface on an unresolvable id.

The UI host follows the ssh::ui_host convention (modules/ssh/lib.zsh — first
CODE_UI_HOSTS entry, default trifle); override with CMUX_APP_HOST.

Log: ~/.local/state/claude-cmux-tab/sync.log (1 MB, one rotation).
"""

import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

CMUX_APP_BIN = "/Applications/cmux.app/Contents/Resources/bin/cmux"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "claude-cmux-tab"
LOG_FILE = STATE_DIR / "sync.log"
SSH_LIB = Path(__file__).resolve().parent.parent.parent / "ssh" / "lib.zsh"
UUID_RE = r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
_TERMINAL_LINE = re.compile(
    rf"""surface\ surface:\S+\s+
         (?P<uuid>{UUID_RE})\s+
         \[terminal\]\s+
         "(?P<title>[^"]*)"
    """,
    re.VERBOSE,
)


def log(outcome: str, *, sid: str = "?", evt: str = "?", name: str = "",
        t0: float | None = None) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        if LOG_FILE.exists() and LOG_FILE.stat().st_size > 1_000_000:
            LOG_FILE.replace(LOG_FILE.with_suffix(".log.1"))
        dur = f" dur_ms={int((time.monotonic() - t0) * 1000)}" if t0 is not None else ""
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        with LOG_FILE.open("a") as f:
            f.write(f"{stamp} evt={evt} sid={sid} name={name} {outcome}{dur}\n")
    except OSError:
        pass


def ui_host() -> str:
    host = os.environ.get("CMUX_APP_HOST")
    if host:
        return host
    try:
        out = subprocess.run(
            ["zsh", "-c", f"source {shlex.quote(str(SSH_LIB))} 2>/dev/null && ssh::ui_host"],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        if out:
            return out
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "trifle"


def is_local() -> bool:
    return os.access(CMUX_APP_BIN, os.X_OK)


def cmux(*args: str, timeout: int = 20) -> str:
    """Run a cmux command against the app socket, locally or over ssh."""
    if is_local():
        cmd = [CMUX_APP_BIN, *args]
    else:
        remote = " ".join(shlex.quote(a) for a in [CMUX_APP_BIN, *args])
        cmd = ["ssh", "-n", ui_host(), f"exec {remote}"]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return res.stdout


def ssh_ps(pids: list[str]) -> str:
    if is_local():
        cmd = ["ps", "-o", "pid=,args=", "-p", ",".join(pids)]
    else:
        cmd = ["ssh", "-n", ui_host(), f"ps -o pid=,args= -p {','.join(pids)}"]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout


def terminal_tabs(tree: str) -> list[tuple[str, str]]:
    """(uuid, title) for every terminal surface in `tree --all` output."""
    return [(m.group("uuid"), m.group("title")) for m in _TERMINAL_LINE.finditer(tree)]


def title_in_sync(title: str, name: str) -> bool:
    if title == name:
        return True
    if len(title) > len(name) and title.endswith(name):
        boundary = title[-len(name) - 1]
        return not (boundary.isalnum() or boundary == "-")
    return False


def any_tab_in_sync(tree: str, name: str) -> bool:
    return any(title_in_sync(t, name) for _, t in terminal_tabs(tree))


def surface_for_zellij(tree: str, zellij_name: str, top_tsv: str, ps_out: str) -> str | None:
    """Deterministic surface resolution: zellij session name -> surface UUID."""
    pid_to_ref: dict[str, str] = {}
    for row in top_tsv.splitlines():
        cols = row.split("\t")
        if len(cols) >= 6 and cols[3] == "process" and cols[5].startswith("surface:"):
            pid_to_ref[cols[4]] = cols[5]
    owner_pat = re.compile(rf"[ /]{re.escape(zellij_name)}( |$)")
    owner = next(
        (line.split()[0] for line in ps_out.splitlines() if owner_pat.search(line)),
        None,
    )
    ref = pid_to_ref.get(owner or "")
    if not ref:
        return None
    line_pat = re.compile(rf"surface {re.escape(ref)} ({UUID_RE})")
    m = line_pat.search(tree)
    return m.group(1) if m else None


def rename_tab(surface: str, name: str) -> bool:
    params = json.dumps({"action": "rename", "tab_id": surface, "title": name})
    try:
        out = cmux("rpc", "tab.action", params)
        acted = json.loads(out).get("surface_id", "")
    except (json.JSONDecodeError, OSError, subprocess.TimeoutExpired):
        return False
    return acted.lower() == surface.lower()


def session_name(sessions_dir: Path, sid: str) -> str | None:
    for f in sessions_dir.glob("*.json"):
        try:
            rec = json.loads(f.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if rec.get("sessionId") == sid:
            return rec.get("name") or None
    return None


def sync_one(sid: str, name: str, zellij_name: str | None, tree: str,
             fetch: dict, *, evt: str, t0: float) -> None:
    """Sync one session's tab; `fetch` lazily caches top/ps across a sweep."""
    if any_tab_in_sync(tree, name):
        log("outcome=in-sync", sid=sid, evt=evt, name=name, t0=t0)
        return
    if is_local():
        surface = os.environ.get("CMUX_SURFACE_ID", "")
        if not surface:
            log("outcome=local-no-surface-env", sid=sid, evt=evt, name=name, t0=t0)
            return
        if surface.lower() not in tree.lower():
            log("outcome=local-stale-surface", sid=sid, evt=evt, name=name, t0=t0)
            return
    else:
        if not zellij_name:
            log("outcome=no-zellij-env", sid=sid, evt=evt, name=name, t0=t0)
            return
        if "top" not in fetch:
            fetch["top"] = cmux("top", "--all", "--processes", "--flat", "--format", "tsv")
            pids = [c.split("\t")[4] for c in fetch["top"].splitlines()
                    if len(c.split("\t")) >= 6 and c.split("\t")[3] == "process"
                    and c.split("\t")[5].startswith("surface:")]
            fetch["ps"] = ssh_ps(pids) if pids else ""
        surface = surface_for_zellij(tree, zellij_name, fetch["top"], fetch["ps"])
        if not surface:
            log(f"outcome=zellij-session-not-found zellij={zellij_name}",
                sid=sid, evt=evt, name=name, t0=t0)
            return
    if rename_tab(surface, name):
        log(f"outcome=renamed surface={surface}", sid=sid, evt=evt, name=name, t0=t0)
    else:
        log(f"outcome=rename-unverified surface={surface}", sid=sid, evt=evt, name=name, t0=t0)


def run_hook() -> None:
    t0 = time.monotonic()
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        payload = {}
    evt = payload.get("hook_event_name", "Stop")
    sid = payload.get("session_id", "")
    transcript = payload.get("transcript_path", "")
    if evt not in ("Stop", "UserPromptSubmit", "SessionStart"):
        log("outcome=gated-event", sid=sid or "?", evt=evt, t0=t0)
        return
    if not sid or not transcript:
        log("outcome=no-session-meta", sid=sid or "?", evt=evt, t0=t0)
        return
    sessions_dir = Path(transcript).parent.parent.parent / "sessions"
    name = session_name(sessions_dir, sid) if sessions_dir.is_dir() else None
    if not name:
        log("outcome=no-name", sid=sid, evt=evt, t0=t0)
        return
    tree = cmux("--id-format", "both", "tree", "--all")
    if not tree:
        log("outcome=no-tree", sid=sid, evt=evt, name=name, t0=t0)
        return
    sync_one(sid, name, os.environ.get("ZELLIJ_SESSION_NAME"), tree, {}, evt=evt, t0=t0)


def proc_env(pid: str, key: str) -> str | None:
    try:
        raw = Path(f"/proc/{pid}/environ").read_bytes()
    except OSError:
        return None
    for chunk in raw.split(b"\0"):
        if chunk.startswith(f"{key}=".encode()):
            return chunk.decode(errors="replace").split("=", 1)[1]
    return None


def run_sweep() -> None:
    """Reconcile every live named session on this box (linux-only: /proc)."""
    tree = cmux("--id-format", "both", "tree", "--all")
    if not tree:
        log("outcome=no-tree", evt="sweep")
        return
    fetch: dict = {}
    for sessions_dir in Path.home().glob(".claude*/sessions"):
        for f in sessions_dir.glob("*.json"):
            t0 = time.monotonic()
            try:
                rec = json.loads(f.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            sid, name, pid = rec.get("sessionId", ""), rec.get("name"), str(rec.get("pid", ""))
            if not (sid and name and pid and Path(f"/proc/{pid}").is_dir()):
                continue
            zellij_name = proc_env(pid, "ZELLIJ_SESSION_NAME")
            if not zellij_name:
                continue  # not a zellij-hosted session (nothing we can resolve)
            if any_tab_in_sync(tree, name):
                continue  # quiet: don't log per-minute no-ops for every session
            sync_one(sid, name, zellij_name, tree, fetch, evt="sweep", t0=t0)


def self_test() -> None:
    cases = [
        ("abstract-iteration-2", "abstract-iteration-2", True),   # exact
        ("fork: abstract-iteration-2", "abstract-iteration-2", True),  # fork prefix
        ("abstract-iteration-2", "abstract-iteration", False),    # old-title extension
        ("my-abstract-iteration", "abstract-iteration", False),   # mid-word
        ("abstract-iteration", "abstract-iteration-2", False),    # rename to longer
        ("12-fruity-emus", "emus", False),                        # suffix behind '-'
    ]
    for title, name, want in cases:
        got = title_in_sync(title, name)
        assert got == want, f"title_in_sync({title!r}, {name!r}) = {got}, want {want}"
    tree_line = ('│   ├── surface surface:47 6F46D6FD-6BED-40F3-B635-E5D92AFBDF54 '
                 '[terminal] "multi-label" [selected]')
    assert terminal_tabs(tree_line) == [("6F46D6FD-6BED-40F3-B635-E5D92AFBDF54", "multi-label")]
    top = "0.0\t1\t1\tprocess\t56773\tsurface:47\tmosh-client"
    ps = ("56773 /opt/mosh-client -# bonbon -- zellij attach "
          "cmux-bonbon-12-fruity-emus | 1.2.3.4 60028")
    assert surface_for_zellij(tree_line, "cmux-bonbon-12-fruity-emus", top, ps) \
        == "6F46D6FD-6BED-40F3-B635-E5D92AFBDF54"
    assert surface_for_zellij(tree_line, "cmux-bonbon-12-fruity", top, ps) is None  # boundary
    print("self-test OK")


def main() -> None:
    if "--self-test" in sys.argv:
        self_test()
    elif "--sweep" in sys.argv:
        try:
            run_sweep()
        except Exception as exc:  # never crash the timer loudly
            log(f"outcome=unexpected-error err={type(exc).__name__}:{exc}", evt="sweep")
    else:
        try:
            run_hook()
        except Exception as exc:  # never block the hook event
            log(f"outcome=unexpected-error err={type(exc).__name__}:{exc}", evt="hook")


if __name__ == "__main__":
    main()
