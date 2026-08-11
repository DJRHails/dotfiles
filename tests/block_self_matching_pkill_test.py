"""Behaviour suite for the block_self_matching_pkill PreToolUse hook.

The hook makes one judgement: does this command match the *caller* against its own pattern?
Both directions are pinned. A missed block kills the agent's own shell mid-command (silently —
the process that would report it is the one that dies) or hangs a wait loop forever. A false
block wedges routine process inspection, including the `pgrep -af` an agent uses to diagnose
exactly this class of bug.

Run: pytest -q tests/block_self_matching_pkill_test.py
     (or: python3 tests/block_self_matching_pkill_test.py)
"""

from __future__ import annotations

import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path

_HOOK = (
    Path(__file__).resolve().parent.parent
    / "modules/claude/hooks/block_self_matching_pkill.py"
)
_spec = importlib.util.spec_from_file_location("block_self_matching_pkill", _HOOK)
assert _spec and _spec.loader
hook = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hook)

# Every one of these matches the shell that runs it, so it kills the caller.
SELF_KILLING = [
    # the exact command that prompted this hook — it killed the shell, and the relaunch
    # queued after it silently never ran
    'pkill -f "glm52_vllm_endpoint"',
    "pkill -f omnibus_narrative_halo.py",
    "pkill -f 'serve.py' && echo done",
    "pkill --full mytrainer",
    "pkill -9 -f mytrainer",
    "pkill -fu djrhails mytrainer",
    # bundled short flags
    "pkill -af mytrainer",
    # wrappers and runners still run it
    "sudo pkill -f mytrainer",
    "timeout 5 pkill -f mytrainer",
    "/usr/bin/pkill -f mytrainer",
    'ssh bonbon "pkill -f mytrainer"',
    "ssh bonbon pkill -f mytrainer",
    'bash -c "pkill -f mytrainer"',
    # buried after a separator
    "echo starting; pkill -f mytrainer",
    "cd /tmp && pkill -f mytrainer",
]

# Safe: matches a process NAME, not the caller's argv — or does not match at all.
ALLOWED = [
    "pkill -x mytrainer",
    "pkill mytrainer",
    "pkill -9 mytrainer",
    "pkill --signal TERM mytrainer",
    "kill -TERM 12345",
    'kill "$(cat /tmp/x.pid)"',
    "kill -0 \"$pid\"",
    # one-shot inspection: the diagnosis path for this very bug
    "pgrep -af mytrainer",
    "pgrep -f mytrainer",
    "pgrep -fl mytrainer | head",
    # merely mentioning it
    'rg "pkill -f" ~/.files',
    "grep -rn 'pkill -f mytrainer' docs/",
    "echo 'never use pkill -f'",
    "which pkill",
]

# A pgrep predicate inside a loop matches the shell evaluating it, so the loop never ends.
HANGING_LOOPS = [
    'while pgrep -f mytrainer > /dev/null; do sleep 5; done',
    'until ! pgrep -f mytrainer; do sleep 2; done',
    'while pgrep -af "train.py" >/dev/null 2>&1; do sleep 10; done',
]

# The same loops, with the caller filtered out.
EXCLUDED_LOOPS = [
    'while pgrep -f mytrainer | grep -v "^$$\\$" > /dev/null; do sleep 5; done',
    'while pgrep -f "$pat" | grep -v $$ >/dev/null; do sleep 5; done',
]


def _run_hook(payload: dict) -> str:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        import sys

        original = sys.stdin
        sys.stdin = io.StringIO(json.dumps(payload))
        try:
            hook.main()
        finally:
            sys.stdin = original
    return buffer.getvalue()


def _run_hook_raw(raw: str) -> str:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        import sys

        original = sys.stdin
        sys.stdin = io.StringIO(raw)
        try:
            hook.main()
        finally:
            sys.stdin = original
    return buffer.getvalue()


def _blocked(command: str) -> bool:
    out = _run_hook({"tool_input": {"command": command}})
    return bool(out) and json.loads(out).get("decision") == "block"


def test_a_full_match_pkill_is_always_blocked() -> None:
    for command in SELF_KILLING:
        assert _blocked(command), f"should block: {command}"


def test_safe_process_matching_is_allowed() -> None:
    for command in ALLOWED:
        assert not _blocked(command), f"should allow: {command}"


def test_a_pgrep_wait_loop_is_blocked() -> None:
    for command in HANGING_LOOPS:
        assert _blocked(command), f"should block: {command}"


def test_a_pgrep_loop_that_excludes_the_caller_is_allowed() -> None:
    for command in EXCLUDED_LOOPS:
        assert not _blocked(command), f"should allow: {command}"


def test_the_pkill_message_names_the_alternatives() -> None:
    """The block has to teach the fix, or it just gets worked around."""
    out = json.loads(_run_hook({"tool_input": {"command": "pkill -f mytrainer"}}))
    reason = out["reason"]
    assert "PID file" in reason
    assert "pkill -x" in reason
    assert "kill -0" in reason


def test_the_pgrep_message_says_inspection_is_fine() -> None:
    """Otherwise the reader concludes pgrep -f is banned and loses their diagnostic tool."""
    out = json.loads(_run_hook({"tool_input": {"command": HANGING_LOOPS[0]}}))
    assert "pgrep -af" in out["reason"]


def test_a_clean_command_produces_no_output() -> None:
    assert _run_hook({"tool_input": {"command": "ls -la"}}) == ""


def test_main_fails_closed_on_an_unreadable_pkill() -> None:
    """Exiting non-zero is NON-blocking to the harness, so a crash would run the command."""
    for raw in (
        '{"tool_input": "pkill -f mytrainer"}',  # tool_input not a dict
        '[{"command": "pkill -f mytrainer"}]',  # payload not a dict
        '{"tool_input": {"command": "pkill -f mytrainer"',  # truncated JSON
    ):
        assert json.loads(_run_hook_raw(raw))["decision"] == "block", raw


def test_unbalanced_quotes_still_block() -> None:
    assert _blocked("pkill -f 'mytrainer")


def test_wants_full_match_reads_bundles_and_long_forms() -> None:
    assert hook.wants_full_match(["-f", "x"])
    assert hook.wants_full_match(["-af"])
    assert hook.wants_full_match(["--full"])
    assert not hook.wants_full_match(["-x", "name"])
    assert not hook.wants_full_match(["-9"])
    # a long option that merely contains an f must not read as -f
    assert not hook.wants_full_match(["--signal", "TERM"])


if __name__ == "__main__":
    for name, case in sorted(globals().items()):
        if name.startswith("test_") and callable(case):
            case()
    print("ok")
