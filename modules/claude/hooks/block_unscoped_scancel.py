#!/usr/bin/env python3
"""PreToolUse hook: block a ``scancel`` that doesn't name the jobs it kills.

Every gantry worker reaches the Slurm clusters as the *same* unix identity
(``djrhails``, uid 2116), so the usual "self-scoped" idioms are not self-scoped at
all — ``scancel -u $USER`` / ``scancel --me`` / ``squeue -u $USER … | xargs scancel``
reap every *peer* worker's queued compute too. That is not hypothetical: a sweep at
2026-07-28T08:15:06Z killed a tp=8 vLLM serve that had waited 6.7h in an 8-GPU queue,
plus four array tasks and a second serve, none of them belonging to the caller.

A cancel is allowed only when it names its targets — explicit job ids, or
``--name=<job-name>``. A user filter is not a target and never makes a cancel safe.

Read the ``scancel`` out of the command with a real shell lexer rather than a regex,
so quoting is honoured: an ``ssh host "scancel -u djrhails"`` is caught, while a
``rg "scancel" docs/`` that merely mentions the word is not.

Run the tests: python3 tests/block_unscoped_scancel_test.py
"""

from __future__ import annotations

import json
import shlex
import sys

# scancel options consuming the NEXT token as their value, so `-u djrhails` is read as
# a user filter rather than a job-id target. Long and short forms of the same option.
VALUE_OPTS = frozenset(
    {
        "-A", "--account",
        "-M", "--clusters",
        "-n", "--name", "--jobname",
        "-p", "--partition",
        "-q", "--qos",
        "-r", "--reservation",
        "-s", "--signal",
        "-t", "--state",
        "-u", "--user",
        "-w", "--nodelist",
        "--wckey",
        "--sibling",
    }
)  # fmt: skip

# Options that narrow a cancel to named jobs — the sanctioned scoped form under a
# shared uid, since a job name is the only per-worker discriminator Slurm carries.
NAME_OPTS = frozenset({"-n", "--name", "--jobname"})

# Command wrappers to peel off before deciding whether `scancel` is the real command.
# `xargs` matters most: `… | xargs scancel` is a live form of the incident.
PLAIN_WRAPPERS = frozenset(
    {"sudo", "time", "nohup", "command", "exec", "builtin", "env"}
)

# Commands that execute a command string handed to them, so a quoted `scancel` inside
# their arguments is a real cancel — `ssh ant-cluster "scancel -u djrhails"` is how a
# worker reaches the cluster in the first place.
COMMAND_RUNNERS = frozenset({"ssh", "bash", "sh", "zsh", "dash", "eval"})

# Wrapper options that consume the next token, so the wrapper's own flags are not
# mistaken for the wrapped command.
WRAPPER_VALUE_OPTS = {
    "xargs": frozenset({"-a", "-d", "-E", "-I", "-i", "-L", "-l", "-n", "-P", "-s", "--replace"}),
    # ssh's value-taking flags; the first bare token after them is the host.
    "ssh": frozenset({"-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l",
                      "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w"}),
}  # fmt: skip

# Shell operators that separate one command from the next. `shlex` with
# punctuation_chars emits these as standalone tokens.
OPERATORS = frozenset(
    {"|", "||", "&", "&&", ";", ";;", "|&", "(", ")", "\n", "<", ">", ">>", "<<"}
)

BLOCK_REASON = (
    "Unscoped `scancel` blocked: every worker shares the one cluster unix identity "
    "(djrhails), so `-u $USER` / `--me` / a bare mass cancel kills PEER workers' queued "
    "jobs, not just yours. A 6.7h-queued tp=8 serve plus four array tasks were destroyed "
    "this way on 2026-07-28.\n"
    "Name the jobs you mean instead:\n"
    "  scancel <jobid> [<jobid> …]     — the ids you submitted (serve id is in the "
    "endpoint record's job_id)\n"
    "  scancel --name=<job-name>       — exact job name (NOT a glob; scancel has no "
    "pattern matching)\n"
    "  scancel-mine                    — every job carrying THIS worker's "
    "$SLURM_JOB_PREFIX, resolved to explicit ids\n"
    "To sweep a name prefix, resolve it to ids first and eyeball them before cancelling:\n"
    "  squeue -h -u djrhails -o '%i %j' | awk '$2 ~ /^<prefix>/ {print $1}'"
)


def _tokenize(command: str) -> list[str]:
    """Split a shell command into tokens, keeping operators as their own tokens."""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        return list(lexer)
    except ValueError:
        # Unbalanced quotes — the shell would reject this anyway. Fall back to a
        # whitespace split so a malformed `scancel -u $USER` still can't sneak past.
        return command.split()


def _split_segments(tokens: list[str]) -> list[list[str]]:
    """Group tokens into individual commands, split on shell operators."""
    segments: list[list[str]] = [[]]
    for token in tokens:
        if token in OPERATORS:
            segments.append([])
        else:
            segments[-1].append(token)
    return [segment for segment in segments if segment]


def _strip_wrappers(segment: list[str]) -> list[str]:
    """Peel leading env assignments and command wrappers off a segment.

    Returns the tokens of the command actually being run, so `xargs -r scancel` and
    `ssh ant-cluster scancel …` both reduce to a `scancel …` head.
    """
    tokens = list(segment)
    while tokens:
        head = tokens[0]
        if (
            "=" in head
            and not head.startswith("-")
            and head.split("=", 1)[0].isidentifier()
        ):
            tokens.pop(0)  # VAR=value prefix
            continue
        if head in PLAIN_WRAPPERS:
            tokens.pop(0)
            continue
        if head == "xargs":
            tokens = _strip_wrapper_args(
                tokens, WRAPPER_VALUE_OPTS["xargs"], drop_host=False
            )
            continue
        break
    return tokens


def _strip_wrapper_args(
    tokens: list[str], value_opts: frozenset[str], *, drop_host: bool
) -> list[str]:
    """Drop a wrapper (tokens[0]), its options, and — for ssh — its host argument."""
    rest = tokens[1:]
    index = 0
    while index < len(rest):
        token = rest[index]
        if not token.startswith("-"):
            break
        index += 1
        if token in value_opts:
            index += 1  # this option's value
    if drop_host and index < len(rest):
        index += 1  # the ssh destination
    return rest[index:]


def _is_job_id(token: str) -> bool:
    """True if the token targets specific job(s) by id.

    Accepts a numeric id, an array element or range (``123_4``, ``123_[1-4]``), and a
    plain variable holding one (``$JOBID``) — a worker legitimately cancels an id it
    just submitted. Rejects a command substitution (``$(squeue …)``), whose expansion
    is unknowable here and is exactly how the fleet-wide sweep was spelled.
    """
    body = token.split("_", 1)
    if body[0].isdigit() and (len(body) == 1 or _is_array_suffix(body[1])):
        return True
    if token.startswith("$") and not token.startswith("$("):
        return token.lstrip("$").strip("{}").isidentifier()
    return False


def _is_array_suffix(suffix: str) -> bool:
    inner = suffix[1:-1] if suffix.startswith("[") and suffix.endswith("]") else suffix
    return bool(inner) and all(char.isdigit() or char in ",-" for char in inner)


def is_scoped(args: list[str]) -> bool:
    """True if these ``scancel`` arguments name the jobs to cancel."""
    index = 0
    while index < len(args):
        token = args[index]
        if token.startswith("--") and "=" in token:
            option, value = token.split("=", 1)
            if option in NAME_OPTS and value:
                return True
        elif token in VALUE_OPTS:
            if token in NAME_OPTS and index + 1 < len(args) and args[index + 1]:
                return True
            index += 1  # skip this option's value
        elif token.startswith("-") and token != "-":
            if token[:2] in NAME_OPTS and len(token) > 2:
                return True  # attached short value, e.g. -nmyjob
        elif _is_job_id(token):
            return True
        index += 1
    return False


def _unscoped_in_segment(segment: list[str]) -> list[list[str]]:
    """Unscoped cancels in one command, descending through any runner that wraps it.

    Only a known command *runner* has its arguments re-analysed, so a command that
    merely mentions the word — ``rg "scancel -u" docs/`` — is left alone.
    """
    args = _strip_wrappers(segment)
    if not args:
        return []
    if args[0] == "scancel":
        return [] if is_scoped(args[1:]) else [args]
    if args[0] not in COMMAND_RUNNERS:
        return []
    if args[0] == "ssh":
        # `ssh ant-cluster scancel -u djrhails` — the remote command is the tail tokens.
        rest = _strip_wrapper_args(args, WRAPPER_VALUE_OPTS["ssh"], drop_host=True)
    else:
        rest = [token for token in args[1:] if not token.startswith("-")]
    if not rest:
        return []
    offenders = _unscoped_in_segment(rest)
    # `ssh ant-cluster "scancel -u djrhails"` — a quoted payload arrives as ONE token
    # carrying a whole command string, so re-lex it.
    for token in rest:
        if token != "scancel" and "scancel" in token:
            offenders.extend(unscoped_scancels(token))
    return offenders


def unscoped_scancels(command: str) -> list[list[str]]:
    """Every ``scancel`` invocation in ``command`` that fails to name its targets."""
    offenders = []
    for segment in _split_segments(_tokenize(command)):
        offenders.extend(_unscoped_in_segment(segment))
    return offenders


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return
    command = (payload.get("tool_input") or {}).get("command") or ""
    if not command or "scancel" not in command:
        return
    if unscoped_scancels(command):
        json.dump({"decision": "block", "reason": BLOCK_REASON}, sys.stdout)


if __name__ == "__main__":
    main()
