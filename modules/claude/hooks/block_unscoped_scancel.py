#!/usr/bin/env python3
"""PreToolUse hook: block a ``scancel`` that doesn't name the jobs it kills.

Every worker reaches the Slurm clusters as the *same* unix account, so the idioms that
read as self-scoped are not: ``scancel -u $USER`` / ``scancel --me`` /
``squeue -u $USER … | xargs scancel`` reap every *peer* worker's queued compute too.
That is not hypothetical — one such sweep destroyed a peer's long-queued multi-GPU serve
and several array tasks, none of them belonging to the caller. The full incident record
lives in the ``runpod-ant-cluster`` skill, which is encrypted at rest.

A cancel is allowed only when it names its targets: explicit job ids, or a job name.
A user filter is not a target and never makes a cancel safe.

Be clear about what "named" does *not* buy you. ``--name`` is an exact match with no
globbing, but an exact name is still not self-scoped under a shared account —
``scancel --name=X`` reaps every worker's job called ``X``. Naming is only peer-safe once
the name carries this worker's ``$SLURM_JOB_PREFIX`` (see ``bin/slurm-job-prefix``),
which is not yet enforced at submit time; until it is, this hook accepts any name and
that residual risk rests on the permission classifier.

The command is read with a real shell lexer rather than a regex, so quoting is honoured:
an ``ssh host "scancel -u djrhails"`` is caught, while an ``rg "scancel" docs/`` that
merely mentions the word is not. Where the parser cannot tell what a segment runs it
fails CLOSED — an unrecognised wrapper around a ``scancel`` is still a ``scancel``,
whether the cancel arrives as a bare token (``srun scancel --me``) or buried in a quoted
argument (``sbatch --wrap 'scancel --me'``). Only the commands that provably cannot run
their arguments — ``MENTION_ONLY_COMMANDS`` and ``LOOKUP_COMMANDS`` — get a pass.

Run the tests: python3 tests/block_unscoped_scancel_test.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path, PurePosixPath

# Claude Code runs this as `python3 <abs path>`, which puts the hooks dir on sys.path — but the
# test harness loads it through importlib from a path, which does not. Anchoring on __file__ makes
# `lib.shell_walk` importable either way; without it the refactor passed in production and failed
# under test, which is the worst possible split for a guard.
sys.path.insert(0, str(Path(__file__).resolve().parent))

# Superset of the scancel options that consume the NEXT token as their value, so
# `-u djrhails` is read as a user filter rather than a job-id target. A spurious entry
# only ever over-blocks, which is the safe direction; a MISSING one under-blocks, because
# the option's value is then free to be mistaken for a job id.
VALUE_OPTS = frozenset(
    {
        "-A", "--account",
        "-M", "--clusters",
        "-n", "--name", "--jobname",
        "-p", "--partition",
        "-q", "--qos",
        "-R", "-r", "--reservation",
        "-s", "--signal",
        "-t", "--state",
        "-u", "--user",
        "-w", "--nodelist",
        "--wckey",
        "--sibling",
    }
)  # fmt: skip

# Options that narrow a cancel to named jobs. See the module docstring: exact, but only
# peer-safe once the name carries this worker's prefix.
NAME_OPTS = frozenset({"-n", "--name", "--jobname"})

# Commands that enumerate many job ids at once. A bare `$VAR` target is trusted only when
# none of these appear in the command, since `IDS=$(squeue …); scancel $IDS` is the
# fleet-wide sweep spelled in two steps. Matched as a SUBSTRING of the raw command as well
# as a token, because a backtick substitution never lexes into tokens of its own —
# `` IDS=`squeue …` `` kept `squeue` glued inside `IDS=`squeue` and waved the sweep through.
QUERY_COMMANDS = frozenset({"squeue", "sacct", "scontrol"})

# The generic shell walking lives in lib/shell_walk.py so this guard and
# block_self_matching_pkill share ONE tokeniser. Aliased to the private names this module already
# used, so nothing below changes: two parsers drifting apart is how one guard grows a hole the
# other does not have.
from lib.shell_walk import (  # noqa: E402
    COMMAND_RUNNERS,
    LOOKUP_COMMANDS,
    MENTION_ONLY_COMMANDS,
    WRAPPER_VALUE_OPTS,
    drop_free_text_values,
    split_operator_run as _split_operator_run,
    split_segments as _split_segments,
    strip_wrapper_args as _strip_wrapper_args,
    strip_wrappers as _strip_wrappers,
    tokenize as _tokenize,
)

BLOCK_REASON = (
    "Unscoped `scancel` blocked: every worker shares the one cluster unix account, so "
    "`-u $USER` / `--me` / a bare mass cancel kills PEER workers' queued jobs, not just "
    "yours. A long-queued multi-GPU serve plus several array tasks were destroyed this "
    "way.\n"
    "Name the jobs you mean instead:\n"
    "  scancel-mine --dry-run          — preview, then drop --dry-run. Cancels only jobs\n"
    "                                    carrying THIS worker's $SLURM_JOB_PREFIX,\n"
    "                                    resolved to explicit ids. Run it as\n"
    "                                    ~/.files/bin/scancel-mine if it is not on PATH.\n"
    "  scancel <jobid> [<jobid> …]     — the ids you submitted (a serve's id is in the "
    "endpoint record's job_id)\n"
    "  scancel --name=<job-name>       — exact job name (NOT a glob; scancel has no "
    "pattern matching). Note this still hits a PEER's job of the same name unless the "
    "name carries your $SLURM_JOB_PREFIX.\n"
    "Prefer scancel-mine over hand-rolling a prefix sweep. If you must, this is the whole "
    "predicate it uses — a literal match so a metacharacter cannot widen it, a non-empty "
    'prefix because awk\'s index(s, "") is 1 for EVERY row, and the `<prefix>-` boundary '
    "so prefix 'worker1' does not also claim peer 'worker10':\n"
    "  squeue -h -u \"$(whoami)\" -o '%i %j' | awk -v p='<prefix>' '\n"
    '    p != "" && index($2, p) == 1 &&\n'
    '      (length($2) == length(p) || substr($2, length(p) + 1, 1) == "-") {print $1}\'\n'
    "Eyeball the ids it prints before cancelling them."
)


def _is_job_id(token: str, *, variables_are_targets: bool) -> bool:
    """True if the token targets specific job(s) by id.

    Accepts a numeric id and an array element or range (``123_4``, ``123_[1-4]``).

    A bare variable (``$JOBID``) is accepted only when ``variables_are_targets`` — i.e.
    when the command contains no job-enumerating query. The hook cannot see what a
    variable holds, so this is a usability concession rather than a guarantee: without
    that condition, ``IDS=$(squeue -u djrhails -h -o %i); scancel $IDS`` is the
    fleet-wide sweep spelled in two steps.
    """
    body = token.split("_", 1)
    if body[0].isdigit() and (len(body) == 1 or _is_array_suffix(body[1])):
        return True
    if variables_are_targets and token.startswith("$"):
        return token.lstrip("$").strip("{}").isidentifier()
    return False


def _is_array_suffix(suffix: str) -> bool:
    inner = suffix[1:-1] if suffix.startswith("[") and suffix.endswith("]") else suffix
    return bool(inner) and all(char.isdigit() or char in ",-" for char in inner)


def _names_a_job(token: str, following: str | None) -> bool:
    """True if this option token narrows the cancel to a named job.

    Covers all three spellings a name can arrive in: ``--name=X``, ``-n X`` (where
    ``following`` is the next token) and the attached short form ``-nmyjob``. An empty
    value narrows nothing, so ``--name=`` and a trailing bare ``-n`` are both False.
    """
    if token.startswith("--") and "=" in token:
        option, attached = token.split("=", 1)
        return option in NAME_OPTS and bool(attached)
    if token in NAME_OPTS:
        return bool(following)
    return token[:2] in NAME_OPTS and len(token) > 2


def is_scoped(args: list[str], *, variables_are_targets: bool) -> bool:
    """True if these ``scancel`` arguments name the jobs to cancel.

    ``variables_are_targets`` is required rather than defaulted: the permissive value was
    the default, so a caller that forgot it silently got the answer that trusts a bare
    ``$VAR`` — which is exactly how the taint came to be dropped on the nested path.
    """
    index = 0
    while index < len(args):
        token = args[index]
        if token.startswith("-") and token != "-":
            following = args[index + 1] if index + 1 < len(args) else None
            if _names_a_job(token, following):
                return True
            if token in VALUE_OPTS:
                index += 1  # skip this option's value, so it is not read as a job id
        elif _is_job_id(token, variables_are_targets=variables_are_targets):
            return True
        index += 1
    return False


def _unscoped_in_segment(
    segment: list[str], *, variables_are_targets: bool
) -> list[list[str]]:
    """Unscoped cancels in one command, descending through any runner that wraps it.

    Only a command that provably cannot run its arguments is let past: one that merely
    prints or searches them (``rg "scancel -u" docs/``) or merely locates a binary
    (``which scancel``). Everything else falls through to ``_unscoped_in_payload``, which
    fails CLOSED on a ``scancel`` anywhere in the arguments — as a bare token
    (``srun scancel --me``) or inside a quoted string (``sbatch --wrap 'scancel --me'``).
    """
    if not segment:
        return []
    raw_head = PurePosixPath(segment[0]).name
    if raw_head in LOOKUP_COMMANDS:
        return []
    if raw_head == "command" and len(segment) > 1 and segment[1] in {"-v", "-V"}:
        return []  # `command -v scancel` asks where it is, it does not run it
    args = _strip_wrappers(segment)
    if not args:
        return []
    head = PurePosixPath(args[0]).name  # `/usr/bin/scancel` is still a scancel
    if head in MENTION_ONLY_COMMANDS:
        return []
    if head == "scancel":
        scoped = is_scoped(args[1:], variables_are_targets=variables_are_targets)
        return [] if scoped else [args]
    if head in COMMAND_RUNNERS:
        return _unscoped_in_runner(
            head, args, variables_are_targets=variables_are_targets
        )
    # Values claimed by a free-text flag are prose, not commands, so they are dropped before the
    # fail-closed scan. Without this the guard blocked its own paperwork — a `git commit -m` or
    # `gh pr create --title` that so much as discusses a cancel was refused, which teaches people
    # to route around the guard rather than heed it.
    return _unscoped_in_payload(
        drop_free_text_values(args[1:]), variables_are_targets=variables_are_targets
    )


def _unscoped_in_payload(
    tokens: list[str], *, variables_are_targets: bool
) -> list[list[str]]:
    """Unscoped cancels among tokens handed to a command we did not recognise.

    Reached whenever the parser cannot say what will run, so it errs towards blocking. A
    quoted payload arrives as ONE token carrying a whole command string, and an option can
    carry it attached (``--wrap=scancel --me``), so we re-lex from the first ``scancel``
    inside the token rather than requiring the token to equal it.
    """
    offenders: list[list[str]] = []
    if "scancel" in tokens:
        cancel_at = tokens.index("scancel")
        offenders.extend(
            _unscoped_in_segment(
                tokens[cancel_at:], variables_are_targets=variables_are_targets
            )
        )
    for token in tokens:
        if token != "scancel" and "scancel" in token:
            offenders.extend(
                _unscoped_in_command(
                    token[token.index("scancel") :],
                    variables_are_targets=variables_are_targets,
                )
            )
    return offenders


def _unscoped_in_runner(
    head: str, args: list[str], *, variables_are_targets: bool
) -> list[list[str]]:
    """Unscoped cancels inside a command that runs a command handed to it."""
    if head == "ssh":
        # `ssh ant-cluster scancel -u djrhails` — the remote command is the tail tokens.
        rest = _strip_wrapper_args(args, WRAPPER_VALUE_OPTS["ssh"], drop_host=True)
    else:
        # Drop the runner's own flags up to the first operand, but do NOT filter flags out
        # of the middle: that detached `-u` from its value in `bash -c scancel -u $USER`
        # and promoted the username to a job-id target.
        rest = _strip_wrapper_args(args, frozenset(), drop_host=False)
    if not rest:
        # An interpreter with no operand reads its script from stdin, so the cancel is in
        # some other segment (`echo 'scancel --me' | bash`). Nothing here to judge.
        return []
    offenders = _unscoped_in_segment(rest, variables_are_targets=variables_are_targets)
    offenders.extend(
        _unscoped_in_payload(rest, variables_are_targets=variables_are_targets)
    )
    return offenders


def _variables_are_targets(command: str, tokens: list[str]) -> bool:
    """True if a bare ``$VAR`` may be trusted as naming specific jobs.

    False as soon as the command enumerates job ids anywhere, because
    ``IDS=$(squeue …); scancel $IDS`` is the fleet-wide sweep in two steps. The raw-text
    check is what catches a backtick substitution, which never lexes into its own tokens.
    """
    if any(PurePosixPath(token).name in QUERY_COMMANDS for token in tokens):
        return False
    return not any(query in command for query in QUERY_COMMANDS)


def unscoped_scancels(command: str) -> list[list[str]]:
    """Every ``scancel`` invocation in ``command`` that fails to name its targets."""
    # True is only the seed: nothing OUTSIDE this command has tainted a `$VAR` yet, and
    # `_unscoped_in_command` ands in whatever this command's own text enumerates.
    return _unscoped_in_command(command, variables_are_targets=True)


def _unscoped_in_command(
    command: str, *, variables_are_targets: bool
) -> list[list[str]]:
    """Every unscoped cancel in ``command``, under an inherited variable-trust decision.

    Nested payloads AND the caller's decision with their own, so the trust is monotonic:
    once anything in the OUTER command enumerated job ids, re-lexing an inner
    ``ssh host "scancel $IDS"`` cannot decide the variable is safe after all.
    """
    tokens = _tokenize(command)
    inherited = variables_are_targets and _variables_are_targets(command, tokens)
    segments = _split_segments(tokens)
    offenders = []
    for segment in segments:
        offenders.extend(_unscoped_in_segment(segment, variables_are_targets=inherited))
    if "scancel" in command and any(_reads_script_from_stdin(s) for s in segments):
        # `echo 'scancel --me' | bash` — the interpreter's script never appears as an
        # argument, so no segment can be judged on its own. The producer is a
        # MENTION_ONLY command, which would otherwise make this the one shape where
        # naming a cancel out loud is enough to run it.
        offenders.append(["scancel"])
    return offenders


def _reads_script_from_stdin(segment: list[str]) -> bool:
    """True if this segment is an interpreter with no script operand, so it reads stdin."""
    args = _strip_wrappers(segment)
    if not args:
        return False
    head = PurePosixPath(args[0]).name
    if head not in COMMAND_RUNNERS or head in {"ssh", "eval"}:
        return False
    return not _strip_wrapper_args(args, frozenset(), drop_host=False)


def _command_from_payload(raw: str) -> str | None:
    """The Bash command in a hook payload, or None if the payload isn't the shape we expect.

    ``json.load`` hands back ``Any``, so every level needs a runtime check — a payload of
    ``[1,2]`` used to raise ``AttributeError``, and a hook that exits non-zero is a
    *non-blocking* error to the harness, i.e. the dangerous command ran anyway.
    """
    try:
        payload = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(payload, dict):
        return None
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    command = tool_input.get("command")
    return command if isinstance(command, str) else None


def main() -> None:
    raw = sys.stdin.read()
    command = _command_from_payload(raw)
    if command is None:
        # Unreadable payload: block only if the raw text mentions a cancel. Wedging every
        # Bash call on a schema change would get this hook deleted, but silently going
        # dark on the one command it exists to stop is worse.
        if "scancel" in raw:
            _emit_block()
        return
    if "scancel" not in command:
        return
    try:
        offenders = unscoped_scancels(command)
    except Exception:  # noqa: BLE001 - a cancel we cannot parse is not provably safe
        offenders = [["scancel"]]
    if offenders:
        _emit_block()


def _emit_block() -> None:
    json.dump({"decision": "block", "reason": BLOCK_REASON}, sys.stdout)


if __name__ == "__main__":
    main()
