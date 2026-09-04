#!/usr/bin/env python3
"""Inventory recent claude sessions across every config store, mark the live ones, and judge the
dead ones finished or unfinished — the automated front half of judge-and-resume (SKILL.md).

  python3 judge-agent-sessions.py [--days 2]          # report; unfinished ones get a resume command
  python3 judge-agent-sessions.py --resume-unfinished # run those resumes on the local host, in turn
  python3 judge-agent-sessions.py --all               # also list one-shot batch workers and stubs

Liveness: every running claude writes ~/.claude*/sessions/<pid>.json (pid, sessionId, cwd, busy/idle
status, derived tab name, process start time). A file is trusted only if its pid is alive AND that
pid's start time matches the recorded one — after a reboot the kernel hands old pids to new
processes, and a crash leaves files behind. This is exact for claude processes on this machine and
needs no statusline scraping; pi and agents on other hosts keep the manual path in SKILL.md.

Verdicts read off the LAST turn of each dead transcript:
  pending-tool  final message is an assistant tool call with no result: died mid-work
  mid-turn      final message is a tool result, or a prompt, the assistant never answered
  asked         final text ends on a question or hands the next step to the user
  self-flagged  final text admits undone work ("not pushed", "still needs", "could not create")
  finished      final text is a completion report with nothing outstanding
The asked / self-flagged patterns probe the final text's opening AND closing paragraphs: a report
leads with its outstanding item ("one step needs you", "It is not pushed") as often as it ends on
it. They are loose on purpose — a false positive costs one extra tab, a miss loses work.
  stub          nothing to resume (/clear-only files, "ready when you are", no assistant text)
A session with exactly one human prompt is a one-shot: a cron/batch worker whose output was already
consumed. Finished one-shots and stubs are hidden without --all; an unfinished one-shot is listed
but never auto-resumed (a killed cron worker is re-run by its cron) unless --all is given.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "rebuild_durable", Path(__file__).with_name("rebuild-durable.py"))
_RD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_RD)

# Every store claude::resume searches (resume-agent-session.py CLAUDE_ROOTS); each holds a
# projects/ tree of transcripts and a sessions/ dir of per-process liveness files.
STORES = {"claude": Path.home() / ".claude", "ant": Path.home() / ".claude-ant",
          "agents": Path.home() / ".agents"}
UNFINISHED = {"pending-tool", "mid-turn", "asked", "self-flagged"}
PROBE_CHARS = 600  # of the final text, the lede and the tail the asked / self-flagged patterns see
# The session file's procStart is UTC in month-day order; `ps -o lstart` is LOCAL time, month-day
# on linux and day-month on macOS. Compare as epochs, never as strings.
PROC_START_UTC = "%a %b %d %H:%M:%S %Y"
PS_LSTART = ("%a %b %d %H:%M:%S %Y", "%a %d %b %H:%M:%S %Y")
START_TOLERANCE = 2.0  # seconds; a recycled pid is off by hours

BATCH_CWD = re.compile(
    r"""(?x)
    ^ /(?:private/)? tmp (?:/|$)   # scratch cwd: a batch worker, never one of the user's tabs
    """)
WRAPPED_PROMPT = re.compile(
    r"""(?x)
    ^ \s* <(?: local-command-caveat | local-command-stdout | command-name | bash-input
              | bash-stdout | bash-stderr | system-reminder | tool_result )   # harness-injected
    """)
ASKED = re.compile(
    r"""(?ix)
      \? \s* $                                              # ends on a question
    | \b tell \s me \b
    | \b let \s me \s know \b
    | \b needs? \s you \b
    | \b (?:one | a) \s (?:confirmation | word | go | tap) \s from \s you \b
    | \b when \s you \s have \b
    | \b run \s this \s once \b
    | \b your \s call \b
    | \b (?:should | shall) \s i \b
    | \b (?:do \s you \s want | would \s you \s like) \b
    | \b which \s (?:do | would) \s you \b
    | \b only \s (?:you | your \s \w+) \s can \b
    """)
SELF_FLAGGED = re.compile(
    r"""(?ix)
      \b not \s (?:yet \s)? (?:pushed | committed | merged | deployed | finished) \b
    | \b still \s needs? \b
    | \b remains? \s (?:unpushed | uncommitted | open | undone) \b
    | \b left \s (?:undone | for \s you | to \s do) \b
    | \b (?:could \s not | couldn't | cannot | can't) \s (?:create | complete | finish) \b
    | \b blocked \s on \b
    """)
STUB_TEXT = re.compile(
    r"""(?ix)
    ready \s when \s you \s are | what \s would \s you \s like \s to \s work \s on
    """)
CLAUDE_PROC = re.compile(
    r"""(?x)
    (?: ^ | / ) claude (?: \s | $ )   # the CLI binary, not Claude.app helpers or claude-code-guide
    """)
COMMAND_NAME = re.compile(
    r"""(?x)
    <command-name> \s* (?P<name> [^<]+? ) \s* </command-name>   # a slash-command invocation
    """)
TAG = re.compile(
    r"""(?x)
    < /? [a-z-]+ >   # harness wrapper tags around a typed prompt
    """)


@dataclass
class Session:
    store: str
    path: Path
    session_id: str
    cwd: str
    title: str
    first_prompt: str
    n_prompts: int
    last_ts: datetime
    verdict: str
    reason: str

    @property
    def one_shot(self) -> bool:
        return self.n_prompts <= 1

    @property
    def repo(self) -> str:
        return _RD.repo(self.cwd) if self.cwd else "home"

    @property
    def slug(self) -> str:
        return slugify(self.title or self.first_prompt)


def prompt_label(text: str) -> str:
    """What the user typed, for the report: the slash command if the prompt was one, else the
    prompt with harness wrapper tags stripped."""
    if m := COMMAND_NAME.search(text):
        return m.group("name")
    return " ".join(TAG.sub(" ", text).split())


def slugify(text: str) -> str:
    """Tab/session-name slug in resume-agent-session.py's [A-Za-z0-9-]+ charset, ≤32 chars."""
    words = re.sub(r"[^A-Za-z0-9]+", " ", text).lower().split()
    out: list[str] = []
    for w in words:
        if len("-".join([*out, w])) > 32:
            break
        out.append(w)
    return "-".join(out) or "session"


def ps(columns: str) -> list[str]:
    return subprocess.run(["ps", "-axww", "-o", columns], capture_output=True,
                          text=True).stdout.splitlines()


def process_starts() -> dict[int, float]:
    """pid -> start epoch for every process, parsed from the local-time `lstart` column."""
    out = {}
    for ln in ps("pid=,lstart="):
        parts = ln.split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        for fmt in PS_LSTART:
            try:
                out[int(parts[0])] = datetime.strptime(parts[1].strip(), fmt).timestamp()
                break
            except ValueError:
                continue
    return out


def recorded_start(info: dict) -> float | None:
    """The session file's own claim about when its process started, as an epoch."""
    try:
        return datetime.strptime(info["procStart"], PROC_START_UTC).replace(
            tzinfo=timezone.utc).timestamp()
    except (KeyError, ValueError, TypeError):
        return None


def live_sessions() -> dict[str, str]:
    """sessionId -> '<busy|idle> pid=<n> <tab name>' for every claude process alive right now,
    judged from the per-process session files; a file whose pid is gone, or now belongs to a
    process started at a different time, is a leftover and ignored."""
    starts = process_starts()
    out = {}
    for store in STORES.values():
        for f in (store / "sessions").glob("*.json"):
            try:
                info = json.loads(f.read_text())
                pid = int(info["pid"])
                sid = info["sessionId"]
            except (OSError, ValueError, KeyError, json.JSONDecodeError):
                continue
            claimed = recorded_start(info)
            if pid not in starts or claimed is None \
                    or abs(starts[pid] - claimed) > START_TOLERANCE:
                continue
            out[sid] = f"{info.get('status', '?')} pid={pid} {info.get('name', '')}".rstrip()
    return out


def claude_process_count() -> int:
    n = 0
    for ln in ps("command="):
        if CLAUDE_PROC.search(ln) and "Claude.app" not in ln:
            n += 1
    return n


def message_text(rec: dict) -> tuple[str, bool]:
    """(text, has_tool_use) for a user/assistant record; tool results render as a marker."""
    content = rec.get("message", {}).get("content")
    if isinstance(content, str):
        return content, False
    parts, tool = [], False
    for block in content or []:
        kind = block.get("type")
        if kind == "text":
            parts.append(block.get("text", ""))
        elif kind == "tool_use":
            tool = True
        elif kind == "tool_result":
            parts.append("<tool_result>")
    return "\n".join(parts), tool


def judge(msgs: list[tuple[str, str, bool]], n_prompts: int) -> tuple[str, str]:
    """(verdict, reason) from the final turn. msgs: (role, text, has_tool_use) in order, with
    trailing harness-injected user records (/clear, local command output) already stripped."""
    assistant_texts = [t for role, t, _ in msgs if role == "assistant" and t.strip()]
    if not msgs or not assistant_texts:
        return "stub", "no assistant text"
    role, text, has_tool = msgs[-1]
    if role == "assistant" and has_tool:
        return "pending-tool", "final message is a tool call with no result"
    if role == "user":
        if text.startswith("<tool_result"):
            return "mid-turn", "tool result never answered"
        return "mid-turn", "prompt never answered"
    final = assistant_texts[-1].rstrip()
    if n_prompts <= 1 and STUB_TEXT.search(final):
        return "stub", "greeting only"
    # Lede + tail, joined so that `$` in ASKED still means the true end of the text.
    probe = final if len(final) <= 2 * PROBE_CHARS else \
        final[:PROBE_CHARS] + "\n" + final[-PROBE_CHARS:]
    if m := ASKED.search(probe):
        return "asked", f"hands the next step to you: {m.group(0).strip()!r}"
    if m := SELF_FLAGGED.search(probe):
        return "self-flagged", f"admits undone work: {m.group(0).strip()!r}"
    return "finished", "completion report"


def parse(path: Path, store: str) -> Session | None:
    """One pass over a transcript: identity, title, human-prompt count, and the judged verdict.
    Sidechain (subagent) records are skipped; the last message timestamp is the activity clock —
    mtime is not, since sync and bookkeeping records bump it."""
    session_id, cwd, title, first_prompt = "", "", "", ""
    n_prompts = 0
    last_ts = ""
    msgs: list[tuple[str, str, bool]] = []
    with path.open() as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("isSidechain"):
                continue
            session_id = session_id or rec.get("sessionId", "")
            cwd = cwd or rec.get("cwd", "")
            if rec.get("type") == "ai-title":
                title = rec.get("aiTitle") or title
            if rec.get("type") not in ("user", "assistant"):
                continue
            text, has_tool = message_text(rec)
            last_ts = rec.get("timestamp") or last_ts
            if rec["type"] == "user" and not WRAPPED_PROMPT.match(text):
                n_prompts += 1
                first_prompt = first_prompt or prompt_label(text)
            msgs.append((rec["type"], text, has_tool))
    if not session_id or not last_ts:
        return None
    while msgs and msgs[-1][0] == "user" and WRAPPED_PROMPT.match(msgs[-1][1]) \
            and not msgs[-1][1].startswith("<tool_result"):
        msgs.pop()
    verdict, reason = judge(msgs, n_prompts)
    when = datetime.fromisoformat(last_ts.replace("Z", "+00:00")).astimezone()
    return Session(store, path, session_id, cwd, title, first_prompt.strip()[:80], n_prompts,
                   when, verdict, reason)


def inventory(days: float) -> list[Session]:
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    out = []
    for store, root in STORES.items():
        for path in (root / "projects").glob("*/*.jsonl"):
            if "/subagents/" in str(path) or path.stat().st_mtime < cutoff.timestamp():
                continue
            s = parse(path, store)
            if s and s.last_ts >= cutoff and not BATCH_CWD.match(s.cwd):
                out.append(s)
    out.sort(key=lambda s: s.last_ts, reverse=True)
    return out


def resume_command(s: Session) -> list[str]:
    return [sys.executable, str(Path(__file__).with_name("resume-agent-session.py")),
            "--kind", "claude", "--id", s.session_id, "--slug", s.slug, "--workspace", s.repo]


def report(sessions: list[Session], live: dict[str, str], show_all: bool) -> list[Session]:
    """Print the grouped inventory; return the sessions a --resume-unfinished pass would resume."""
    def row(s: Session, verdict: str, note: str) -> str:
        label = s.title or s.first_prompt
        return (f"  {verdict:<13} {s.store:<6} {s.session_id[:8]}  {s.repo:<22} "
                f"{s.last_ts:%m-%d %H:%M}  {label[:44]:<44}  {note}")

    groups: dict[str, list[str]] = {"UNFINISHED": [], "LIVE": [], "FINISHED": [], "HIDDEN": []}
    to_resume = []
    for s in sessions:
        if s.session_id in live:
            groups["LIVE"].append(row(s, "live", live[s.session_id]))
        elif s.verdict in UNFINISHED:
            tag = " (one-shot)" if s.one_shot else ""
            groups["UNFINISHED"].append(row(s, s.verdict + tag, s.reason))
            if show_all or not s.one_shot:
                to_resume.append(s)
        elif s.verdict == "finished" and not s.one_shot:
            groups["FINISHED"].append(row(s, "finished", s.reason))
        else:
            groups["HIDDEN"].append(row(s, s.verdict + (" (one-shot)" if s.one_shot else ""),
                                        s.reason))
    for name in ("UNFINISHED", "LIVE", "FINISHED"):
        print(f"{name} ({len(groups[name])})")
        print("\n".join(groups[name]) or "  -")
    hidden = groups["HIDDEN"]
    if show_all:
        print(f"ONE-SHOT / STUB ({len(hidden)})")
        print("\n".join(hidden) or "  -")
    else:
        print(f"hidden: {len(hidden)} finished one-shot workers and stubs (--all to list)")
    if to_resume:
        print("\nresume the unfinished ones (or pass --resume-unfinished):")
        here = str(Path(__file__).parent) + "/"
        for s in to_resume:
            print("  " + " ".join(resume_command(s)[1:]).replace(here, ""))
    return to_resume


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--days", type=float, default=2, help="activity window (default 2)")
    ap.add_argument("--all", action="store_true",
                    help="list finished one-shot workers and stubs; let --resume-unfinished "
                         "resume unfinished one-shots too")
    ap.add_argument("--resume-unfinished", action="store_true",
                    help="run resume-agent-session.py for every unfinished session, sequentially")
    a = ap.parse_args()

    live = live_sessions()
    sessions = inventory(a.days)
    to_resume = report(sessions, live, a.all)
    unmatched = claude_process_count() - len(live)
    if unmatched > 0:
        print(f"\nWARNING: {unmatched} claude process(es) have no trusted sessions/<pid>.json — "
              "an older claude, or a file this check rejected; a 'dead' verdict above may be "
              "wrong, so eyeball the tabs before resuming.")
    if not a.resume_unfinished:
        return 0
    failed = 0
    for s in to_resume:
        print(f"\n== resuming {s.session_id[:8]} ({s.slug}) into {s.repo}")
        if subprocess.run(resume_command(s)).returncode:
            failed += 1
    print(f"\nresumed {len(to_resume) - failed}/{len(to_resume)} unfinished sessions")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
