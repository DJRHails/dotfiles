#!/usr/bin/env python3
"""PreToolUse hook: block ``pkill -f`` (and a ``pgrep -f`` wait loop), which match the caller.

``pkill -f PATTERN`` matches PATTERN against every process's **full command line** — including
the shell the agent is running the ``pkill`` inside, whose argv contains PATTERN because PATTERN
is right there in the command. So the pattern that names the target also names the caller, and
``pkill`` has no flag that excludes it.

This is not theoretical. A worker ran ``pkill -f "glm52_vllm_endpoint"`` to stop a launcher; it
killed its own shell (exit 144), so the *next* command in that same invocation — relaunching the
serve with a corrected config — silently never ran. The failure was only caught minutes later
because the expected log file did not exist. There is no error message for this: the process that
would have reported it is the one that died.

The ``pgrep -f`` twin hangs instead of dying: a wait loop whose predicate is
``pgrep -f "$pattern"`` always matches the shell evaluating it, so the loop never sees its job
finish and blocks forever. That cost ten hours twice in one session, the second time after
"fixing" it by changing the pattern.

**Policy.** ``pkill -f`` is blocked outright — there is no safe form of it, so there is no flag
combination to teach. ``pgrep -f`` is blocked ONLY inside a loop construct and only when nothing
in the command excludes the caller: a one-shot ``pgrep -af foo`` is how you *diagnose* this class
of bug and stays allowed, because a guard that blocks its own diagnosis gets deleted.

The command is read with the shared shell lexer (``lib/shell_walk``), so quoting is honoured:
``ssh host "pkill -f foo"`` is caught while ``rg "pkill -f" docs/`` is not. An unrecognised
wrapper around a ``pkill`` is still a ``pkill`` — it fails CLOSED.

Run the tests: python3 tests/block_self_matching_pkill_test.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path, PurePosixPath

# Anchored on __file__ so the import works both as `python3 <abs path>` (Claude Code) and when a
# test harness loads this module from a path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.shell_walk import (  # noqa: E402
    COMMAND_RUNNERS,
    LOOKUP_COMMANDS,
    MENTION_ONLY_COMMANDS,
    WRAPPER_VALUE_OPTS,
    split_segments,
    strip_wrapper_args,
    strip_wrappers,
    tokenize,
)

# The two process-matching commands this guard covers. `killall` is deliberately absent: it matches
# on process NAME only and has no full-command-line mode, so it cannot match the caller's argv.
PKILL = "pkill"
PGREP = "pgrep"
MATCHERS = frozenset({PKILL, PGREP})

# Long forms that turn on full-command-line matching.
FULL_LONG_OPTS = frozenset({"--full"})

# Shell keywords that make a `pgrep` a *predicate* rather than a one-shot look. Only in this
# context does a self-matching pgrep hang rather than merely print an extra line.
LOOP_KEYWORDS = frozenset({"while", "until", "for"})

PKILL_REASON = (
    "`pkill -f` blocked: `-f` matches the FULL command line, and the shell running this very "
    "command has your pattern in its argv — so pkill matches the caller and kills your own "
    "shell. It happened here: `pkill -f \"glm52_vllm_endpoint\"` killed the shell mid-command, "
    "so the relaunch queued after it silently never ran, with no error (the process that would "
    "have reported it was the one that died). pkill has no self-exclude flag, so there is no "
    "safe way to spell this.\n"
    "Use one of these instead:\n"
    "  PID file (best)   pid=$!; echo \"$pid\" > /tmp/x.pid   …then   kill \"$(cat /tmp/x.pid)\"\n"
    "                    and test liveness with `kill -0 \"$pid\"`, never a name pattern.\n"
    "  exact name        pkill -x <process-name>   — matches the NAME, not the argv, so it "
    "cannot match your shell.\n"
    "  explicit exclude  pgrep -f \"$pat\" | grep -v \"^$$\\$\" | xargs -r kill\n"
    "If you are killing a job you launched in this session, you already have its PID — prefer it."
)

PGREP_REASON = (
    "Self-matching `pgrep -f` in a loop blocked: `-f` matches the FULL command line, so the "
    "shell evaluating the loop condition matches your own pattern and the loop never sees its "
    "job finish — it blocks forever. That cost ten hours twice in one session.\n"
    "Use one of these instead:\n"
    "  PID file (best)   while kill -0 \"$(cat /tmp/x.pid)\" 2>/dev/null; do sleep 5; done\n"
    "  exclude self      while pgrep -f \"$pat\" | grep -v \"^$$\\$\" >/dev/null; do sleep 5; done\n"
    "A one-shot `pgrep -af <pattern>` to SEE what matches is fine and is not blocked — that is "
    "how you diagnose this."
)


def _bare_name(token: str) -> str:
    """``/usr/bin/pkill`` -> ``pkill``, so a path-qualified call is still recognised."""
    return PurePosixPath(token).name


def wants_full_match(args: list[str]) -> bool:
    """True if these args turn on full-command-line matching (``-f`` in any spelling).

    Handles bundled short flags (``-af``, ``-fl``), because ``pgrep -af foo`` is by far the most
    common way to write it and a check for the exact token ``-f`` misses every bundle.
    """
    for token in args:
        if token in FULL_LONG_OPTS:
            return True
        if token.startswith("--"):
            continue
        if token.startswith("-") and len(token) > 1 and "f" in token[1:]:
            return True
    return False


def excludes_self(command: str) -> bool:
    """True if the command visibly filters the caller out of the match.

    A deliberate heuristic, and stated as one: it looks for the shell's own pid (``$$``) together
    with a ``grep -v``. It cannot verify the filter is *correct* — only that the author thought
    about self-matching at all, which is enough to stop nagging them.
    """
    return "$$" in command and "grep -v" in command


def _offenders_in_segment(segment: list[str], *, in_loop: bool, self_excluded: bool) -> list[str]:
    """The matcher commands in one segment that this guard blocks; empty when clean."""
    tokens = strip_wrappers(segment)
    if not tokens:
        return []
    head = _bare_name(tokens[0])
    if head in MENTION_ONLY_COMMANDS or head in LOOKUP_COMMANDS:
        return []  # arguments are data, or a "where does this live" lookup
    if head in COMMAND_RUNNERS:
        return _offenders_in_runner(tokens, in_loop=in_loop, self_excluded=self_excluded)
    if head in MATCHERS:
        return _verdict(head, tokens[1:], in_loop=in_loop, self_excluded=self_excluded)
    # Fail closed: an unrecognised head may still run a matcher handed to it as an argument.
    return _scan_for_matchers(tokens[1:], in_loop=in_loop, self_excluded=self_excluded)


def _verdict(head: str, args: list[str], *, in_loop: bool, self_excluded: bool) -> list[str]:
    """Whether one matcher invocation is blocked, given its args and context."""
    if not wants_full_match(args):
        return []  # name matching (`pkill -x foo`) cannot match the caller's argv
    if head == PKILL:
        return [PKILL]  # no safe form exists
    if in_loop and not self_excluded:
        return [PGREP]
    return []


def _scan_for_matchers(tokens: list[str], *, in_loop: bool, self_excluded: bool) -> list[str]:
    """Look for a matcher buried in an unrecognised command's arguments (fail-closed path)."""
    offenders: list[str] = []
    for index, token in enumerate(tokens):
        name = _bare_name(token)
        if name in MATCHERS:
            offenders.extend(
                _verdict(name, tokens[index + 1 :], in_loop=in_loop, self_excluded=self_excluded)
            )
    return offenders


def _offenders_in_runner(tokens: list[str], *, in_loop: bool, self_excluded: bool) -> list[str]:
    """Recurse into a command runner's payload — `ssh host "pkill -f foo"` really does pkill."""
    head = _bare_name(tokens[0])
    value_opts = WRAPPER_VALUE_OPTS.get(head, frozenset())
    rest = strip_wrapper_args(tokens, value_opts, drop_host=head == "ssh")
    offenders: list[str] = []
    for token in rest:
        name = _bare_name(token)
        if name in MATCHERS:
            # a bare token: `ssh host pkill -f foo`
            index = rest.index(token)
            offenders.extend(
                _verdict(name, rest[index + 1 :], in_loop=in_loop, self_excluded=self_excluded)
            )
            continue
        if any(matcher in token for matcher in MATCHERS):
            # a quoted payload: `ssh host "pkill -f foo"` — re-lex it as its own command
            offenders.extend(blocked_matchers(token))
    return offenders


def blocked_matchers(command: str) -> list[str]:
    """Every matcher invocation in ``command`` that this guard blocks; empty when clean."""
    tokens = tokenize(command)
    in_loop = any(token in LOOP_KEYWORDS for token in tokens)
    self_excluded = excludes_self(command)
    offenders: list[str] = []
    for segment in split_segments(tokens):
        offenders.extend(
            _offenders_in_segment(segment, in_loop=in_loop, self_excluded=self_excluded)
        )
    return offenders


def _command_from_payload(raw: str) -> str | None:
    try:
        payload = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None
    if not isinstance(payload, dict):
        return None
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    command = tool_input.get("command")
    return command if isinstance(command, str) else None


def _emit_block(reason: str) -> None:
    json.dump({"decision": "block", "reason": reason}, sys.stdout)


def main() -> None:
    raw = sys.stdin.read()
    command = _command_from_payload(raw)
    if command is None:
        # Unreadable payload: block only if the raw text mentions a matcher. Wedging every Bash
        # call on a schema change would get this hook deleted; going dark on the one command it
        # exists to stop is worse.
        if PKILL in raw:
            _emit_block(PKILL_REASON)
        return
    if not any(matcher in command for matcher in MATCHERS):
        return
    try:
        offenders = blocked_matchers(command)
    except Exception:  # noqa: BLE001 - a matcher we cannot parse is not provably safe
        offenders = [PKILL] if PKILL in command else []
    if PKILL in offenders:
        _emit_block(PKILL_REASON)
        return
    if PGREP in offenders:
        _emit_block(PGREP_REASON)


if __name__ == "__main__":
    main()
