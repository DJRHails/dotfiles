"""Behaviour suite for the block_unscoped_scancel PreToolUse hook.

The hook's whole job is a scope judgement: under the shared cluster account, a cancel is
safe only when it NAMES the jobs it kills. Both directions are pinned — a missed block
destroys a peer worker's queued compute, and a false block wedges routine cluster work.

Run: pytest -q tests/block_unscoped_scancel_test.py
     (or: python3 tests/block_unscoped_scancel_test.py)
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
    # the exact shape of the sweep that prompted this hook
    "squeue -u $USER -h -o %i | xargs scancel",
    "squeue -u djrhails -h -o %i | xargs -r scancel",
    "scancel $(squeue -u djrhails -h -o %i)",
    "squeue -h -o %i | parallel scancel",
    "squeue -h -o %i | parallel -j4 scancel {}",
    # mass selectors: a filter is not a target
    "scancel -p general",
    "scancel --partition=general",
    "scancel --qos=low",
    "scancel -t PENDING",
    "scancel --state=PENDING -u djrhails",
    "scancel -w node042",
    # `-R` is --reservation's real short form; if it were unknown, its value would be
    # misread as a job id and the -u sweep waved through
    "scancel -R myresv -u djrhails",
    "scancel -R 1234 -u djrhails",
    # the shared-account alias that used to ship in modules/slurm/aliases.zsh
    "scancel -u $(whoami)",
    # reached over ssh, quoted and unquoted
    'ssh ant-cluster "scancel -u djrhails"',
    "ssh ant-cluster scancel -u djrhails",
    "ssh eur-cluster 'scancel --me'",
    "ssh -o StrictHostKeyChecking=no ant-cluster 'scancel -u $USER'",
    "ssh ant-cluster -- scancel --me",  # `--` terminator before the remote command
    "ssh ant-cluster -t scancel --me",  # option AFTER the host
    "bash -c 'scancel -u djrhails'",
    # a redirect's file-descriptor digit must not be read as a job id
    "scancel -u djrhails 2>/dev/null",
    "scancel --me 2>&1",
    "scancel -u $USER 2>&1 | tee /tmp/x.log",
    "scancel --me 1>/dev/null 2>&1",
    "squeue -h -o %i | xargs scancel 2>/dev/null",
    # a newline separates commands just as `;` and `&&` do
    "cd /workspace-vast\nscancel -u djrhails",
    "squeue -u djrhails -h -o %i\nscancel --me",
    "set -e\nscancel -u $USER",
    "cd /tmp\nscancel -u djrhails\necho done",
    # any path spelling is still a scancel
    "/usr/bin/scancel -u djrhails",
    "/opt/slurm/bin/scancel --me",
    "./scancel --me",
    # hidden behind wrappers, known and unknown
    "sudo scancel -u djrhails",
    "sudo -n scancel -u djrhails",  # wrapper flag must not stop the peel
    "env -i scancel -u djrhails",
    "timeout 60 scancel -u djrhails",
    "nice scancel --me",
    "setsid scancel --me",
    "stdbuf -o0 scancel -u djrhails",
    "flock /tmp/lock scancel --me",
    "watch -n5 scancel --me",
    "srun scancel --me",
    "find . -name x -exec scancel -u djrhails {} +",
    "cd /workspace-vast && scancel -u $USER",
    # shell keywords head the segment once it is split on `;`
    "if true; then scancel --me; fi",
    "for i in 1 2; do scancel --me; done",
    "squeue -h -o %i | while read j; do scancel -u djrhails; done",
    # a $VAR is not a target when the command also enumerates jobs — the sweep in two steps
    "IDS=$(squeue -u djrhails -h -o %i); scancel $IDS",
    "for j in $(squeue -u djrhails -h -o %i); do scancel $j; done",
    "ids=$(squeue --me -h -o %i)\nscancel $ids",
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
    "/usr/bin/scancel 1937678",
    "scancel 1937678 2>/dev/null",  # fd digit stripped, real id still found
    "scancel --name=serve-under-test",
    "scancel -n serve-under-test",
    "scancel -nserve-under-test",
    "scancel --jobname=eval-under-test",
    # a user filter alongside a real target is fine — the name still narrows it
    "scancel -u djrhails --name=serve-under-test",
    "scancel -u $USER -n eval-under-test",
    "scancel --state=PENDING --name=eval-under-test",
    "ssh ant-cluster 'scancel 1937678'",
    "ssh ant-cluster scancel --name=serve-under-test",
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

# Forms the hook ALLOWS that are not actually peer-safe, recorded so the gap is visible
# rather than assumed. `scancel --name=X` is an exact match, but it cancels every worker's
# job called X — naming is only peer-safe once the name carries this worker's
# $SLURM_JOB_PREFIX, which is not yet enforced at submit time. Tightening this belongs
# with the submit-side naming change; until then it rests on the permission classifier.
KNOWN_NOT_PEER_SAFE = [
    "scancel --name=serve-under-test",
    "scancel --jobname=eval-under-test",
]

# Forms the hook BLOCKS that are arguably fine, recorded so the over-blocking is a
# deliberate, visible choice. Over-blocking is the safe direction: the block message names
# the alternatives, whereas an under-block is unrecoverable.
KNOWN_OVERBLOCK = [
    'scancel "${job_ids[@]}"',  # the idiom bin/scancel-mine itself uses internally
    "squeue -j $JOBID; scancel $JOBID",  # check-then-cancel: the query taints the $VAR
]


def _failures(commands: list[str], *, want_blocked: bool) -> list[str]:
    """Collect every mismatch, so one regression doesn't mask the rest of the corpus."""
    return [
        command
        for command in commands
        if bool(hook.unscoped_scancels(command)) is not want_blocked
    ]


def test_unscoped_cancels_are_blocked() -> None:
    missed = _failures(UNSCOPED, want_blocked=True)
    assert not missed, f"should be blocked but were allowed: {missed}"


def test_scoped_and_unrelated_commands_pass() -> None:
    blocked = _failures(SCOPED, want_blocked=False)
    assert not blocked, f"should be allowed but were blocked: {blocked}"


def test_known_gaps_are_still_gaps() -> None:
    """Pin the documented limits, so closing one is a deliberate edit here."""
    assert not _failures(KNOWN_NOT_PEER_SAFE, want_blocked=False)
    assert not _failures(KNOWN_OVERBLOCK, want_blocked=True)


def test_a_file_descriptor_is_not_a_job_id() -> None:
    """The bug this suite exists to keep closed: `2>` used to look like job 2."""
    tokens = hook._tokenize("scancel -u djrhails 2>/dev/null")
    segments = hook._split_segments(tokens)
    assert segments[0] == ["scancel", "-u", "djrhails"], segments


def test_a_newline_separates_commands() -> None:
    segments = hook._split_segments(hook._tokenize("cd /tmp\nscancel --me"))
    assert ["scancel", "--me"] in segments, segments


def _run_hook(payload: object) -> str:
    """Drive main() exactly as the harness does: JSON on stdin, decision on stdout."""
    return _run_hook_raw(json.dumps(payload))


def _run_hook_raw(raw: str) -> str:
    buffer = io.StringIO()
    with patch("sys.stdin", io.StringIO(raw)), redirect_stdout(buffer):
        hook.main()
    return buffer.getvalue()


def test_main_emits_block_decision() -> None:
    output = _run_hook({"tool_input": {"command": "scancel -u $USER"}})
    decision = json.loads(output)
    assert decision["decision"] == "block"
    # The reason is the whole remediation path; if it drifts, the agent gets a block with
    # no way forward.
    assert "scancel-mine" in decision["reason"]
    assert "index($2, p)" in decision["reason"], (
        "recommend a literal, not a regex, match"
    )


def test_main_stays_silent_on_scoped_cancel() -> None:
    assert _run_hook({"tool_input": {"command": "scancel 1937678"}}) == ""


def test_main_tolerates_malformed_input() -> None:
    """A hook that crashes on unexpected payloads is a hook that gets disabled."""
    assert _run_hook({}) == ""
    assert _run_hook({"tool_input": None}) == ""
    assert _run_hook({"tool_input": {"command": None}}) == ""
    assert _run_hook({"tool_input": {"command": ""}}) == ""
    assert _run_hook_raw("not json at all") == ""
    assert _run_hook([1, 2]) == ""
    assert _run_hook({"tool_input": {"command": 12345}}) == ""


def test_main_fails_closed_on_an_unreadable_cancel() -> None:
    """A payload we can't parse goes dark on the one command the hook exists to stop.

    Exiting non-zero is a NON-blocking error to the harness, so a crash would run the
    command. Block instead whenever the raw text mentions a cancel.
    """
    for raw in (
        '{"tool_input": "scancel -u $USER"}',  # tool_input not a dict
        '[{"command": "scancel --me"}]',  # payload not a dict
        '{"tool_input": {"command": "scancel --me"',  # truncated JSON
    ):
        assert json.loads(_run_hook_raw(raw))["decision"] == "block", raw
    # unbalanced quotes still must not let an unscoped cancel through
    assert json.loads(_run_hook({"tool_input": {"command": "scancel -u $USER '"}}))[
        "decision"
    ]


if __name__ == "__main__":
    for name, case in sorted(globals().items()):
        if name.startswith("test_") and callable(case):
            case()
    print("ok")
