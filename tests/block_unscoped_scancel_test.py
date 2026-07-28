"""Behaviour suite for the block_unscoped_scancel PreToolUse hook.

The hook's whole job is a scope judgement: under the shared cluster uid, a cancel is
safe only when it NAMES the jobs it kills. Both directions are pinned — a missed block
destroys a peer worker's queued compute (the 2026-07-28 sweep), and a false block
wedges routine cluster work.

Run: pytest -q tests/block_unscoped_scancel_test.py  (or: python3 tests/block_unscoped_scancel_test.py)
"""

from __future__ import annotations

import importlib.util
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

_HOOK = (
    Path(__file__).resolve().parent.parent
    / "modules/claude/hooks/block_unscoped_scancel.py"
)
_spec = importlib.util.spec_from_file_location("block_unscoped_scancel", _HOOK)
assert _spec and _spec.loader
hook = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hook)

# Cancels that do NOT name their targets — every one of these reaps peer workers' jobs.
UNSCOPED = [
    "scancel -u $USER",
    "scancel -u djrhails",
    "scancel --user=djrhails",
    "scancel --user djrhails",
    "scancel --me",
    "scancel",
    # the exact shape of the 2026-07-28 sweep
    "squeue -u $USER -h -o %i | xargs scancel",
    "squeue -u djrhails -h -o %i | xargs -r scancel",
    "scancel $(squeue -u djrhails -h -o %i)",
    # mass selectors: a filter is not a target
    "scancel -p general",
    "scancel --partition=general",
    "scancel --qos=low",
    "scancel -t PENDING",
    "scancel --state=PENDING -u djrhails",
    "scancel -w node042",
    # the shared-uid alias that used to ship in modules/slurm/aliases.zsh
    "scancel -u $(whoami)",
    # reached over ssh, quoted and unquoted
    'ssh ant-cluster "scancel -u djrhails"',
    "ssh ant-cluster scancel -u djrhails",
    "ssh eur-cluster 'scancel --me'",
    "ssh -o StrictHostKeyChecking=no ant-cluster 'scancel -u $USER'",
    "bash -c 'scancel -u djrhails'",
    # hidden behind other commands / wrappers
    "sudo scancel -u djrhails",
    "cd /workspace-vast && scancel -u $USER",
    "scancel --name= -u djrhails",  # empty name narrows nothing
    "echo starting; scancel --me; echo done",
]

# Cancels that name their targets, plus commands that merely mention the word.
SCOPED = [
    "scancel 1937678",
    "scancel 1937678 1939790",
    "scancel 1940275_11",
    "scancel 1940275_[11-14]",
    "scancel $JOBID",
    "scancel ${JOB_ID}",
    "scancel --name=vllm-serve-glm-5-2-fp8",
    "scancel -n vllm-serve-glm-5-2-fp8",
    "scancel -nvllm-serve-glm-5-2-fp8",
    "scancel --jobname=mmlu-pro-cap",
    # a user filter alongside a real target is fine — the name still narrows it
    "scancel -u djrhails --name=vllm-serve-glm",
    "scancel -u $USER -n mmlu-pro-cap",
    "scancel --state=PENDING --name=mmlu-pro-cap",
    "ssh ant-cluster 'scancel 1937678'",
    "ssh ant-cluster scancel --name=vllm-serve-glm",
    # read-only Slurm work must never be blocked
    "squeue -u djrhails",
    "sacct -j 1937678",
    "sacct -u djrhails -S 07:55 -E 08:35",
    "scontrol show job 1937678",
    # commands that only TALK about scancel
    "rg -n 'scancel' docs/",
    'rg "scancel -u" ~/.claude/skills',
    "rg -n 'scancel --me' modules/",
    "echo 'never run scancel -u $USER'",
    "grep -r 'scancel -u djrhails' .",
    # the sanctioned helper is its own command, not a scancel
    "scancel-mine",
    "scancel-mine --dry-run",
]


def test_unscoped_cancels_are_blocked() -> None:
    for command in UNSCOPED:
        assert hook.unscoped_scancels(command), f"should be blocked: {command!r}"


def test_scoped_and_unrelated_commands_pass() -> None:
    for command in SCOPED:
        assert not hook.unscoped_scancels(command), f"should be allowed: {command!r}"


def _run_hook(payload: object) -> str:
    """Drive main() exactly as the harness does: JSON on stdin, decision on stdout."""
    buffer = io.StringIO()
    with patch("sys.stdin", io.StringIO(json.dumps(payload))), redirect_stdout(buffer):
        hook.main()
    return buffer.getvalue()


def test_main_emits_block_decision() -> None:
    output = _run_hook({"tool_input": {"command": "scancel -u $USER"}})
    assert json.loads(output)["decision"] == "block"


def test_main_stays_silent_on_scoped_cancel() -> None:
    assert _run_hook({"tool_input": {"command": "scancel 1937678"}}) == ""


def test_main_tolerates_malformed_input() -> None:
    """A hook that crashes on unexpected payloads is a hook that gets disabled."""
    assert _run_hook({}) == ""
    assert _run_hook({"tool_input": None}) == ""
    assert _run_hook({"tool_input": {"command": None}}) == ""
    assert _run_hook({"tool_input": {"command": ""}}) == ""
    # unbalanced quotes still must not let an unscoped cancel through
    assert json.loads(_run_hook({"tool_input": {"command": "scancel -u $USER '"}}))[
        "decision"
    ]


if __name__ == "__main__":
    test_unscoped_cancels_are_blocked()
    test_scoped_and_unrelated_commands_pass()
    test_main_emits_block_decision()
    test_main_stays_silent_on_scoped_cancel()
    test_main_tolerates_malformed_input()
    print("ok")
