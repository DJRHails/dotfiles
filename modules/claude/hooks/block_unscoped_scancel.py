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
fails CLOSED — an unrecognised wrapper around a ``scancel`` is still a ``scancel``.

Run the tests: python3 tests/block_unscoped_scancel_test.py
"""

from __future__ import annotations

import json
import shlex
import sys
from pathlib import PurePosixPath

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
# fleet-wide sweep spelled in two steps.
QUERY_COMMANDS = frozenset({"squeue", "sacct"})

# Wrappers to peel off before deciding whether `scancel` is the real command. Not
# exhaustive, and it does not need to be: an unrecognised head falls through to the
# fail-closed scan in `_unscoped_in_segment`. `xargs` takes value-options, so it is
# handled separately below.
PLAIN_WRAPPERS = frozenset(
    {
        "sudo", "doas", "time", "nohup", "command", "exec", "builtin", "env",
        "timeout", "nice", "ionice", "stdbuf", "setsid", "flock", "watch",
    }
)  # fmt: skip

# Shell keywords that can head a segment once it is split on `;`, so the real command
# follows them: `if …; then scancel --me; fi`.
SHELL_KEYWORDS = frozenset({"then", "do", "else", "elif", "{", "}", "!", "--"})

# Commands whose arguments are DATA, not commands — they can only ever *mention* a
# cancel. Listing them keeps `rg 'scancel -u' docs/` out of the fail-closed scan below;
# a missing entry over-blocks, which is the direction we want to err in.
MENTION_ONLY_COMMANDS = frozenset(
    {
        "rg", "grep", "egrep", "fgrep", "ag", "ack", "echo", "printf", "cat", "sed",
        "awk", "head", "tail", "less", "more", "diff", "man", "comm", "sort", "uniq",
    }
)  # fmt: skip

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

# Operators that redirect rather than separate. They still end a command, but the token
# before them may be a file-descriptor number (`2>/dev/null`), which must not be read as
# a job id — that alone turned a blocked sweep into an allowed one.
REDIRECT_OPERATORS = frozenset({"<", ">", ">>", "<<", "<<<", ">&", "<&", "&>", ">|"})

# Shell operators that separate one command from the next. `shlex` with
# punctuation_chars emits these as standalone tokens; `\n` is inserted by `_tokenize`,
# which lexes line by line (shlex treats a newline as ordinary whitespace).
OPERATORS = (
    frozenset({"|", "||", "&", "&&", ";", ";;", "|&", "(", ")", "\n"})
    | REDIRECT_OPERATORS
)

BLOCK_REASON = (
    "Unscoped `scancel` blocked: every worker shares the one cluster unix account, so "
    "`-u $USER` / `--me` / a bare mass cancel kills PEER workers' queued jobs, not just "
    "yours. A long-queued multi-GPU serve plus several array tasks were destroyed this "
    "way.\n"
    "Name the jobs you mean instead:\n"
    "  scancel-mine --dry-run          — preview, then drop --dry-run. Cancels only jobs\n"
    "                                    carrying THIS worker's $SLURM_JOB_PREFIX,\n"
    "                                    resolved to explicit ids. Run it from\n"
    "                                    $DOTFILES/bin if it is not on PATH.\n"
    "  scancel <jobid> [<jobid> …]     — the ids you submitted (a serve's id is in the "
    "endpoint record's job_id)\n"
    "  scancel --name=<job-name>       — exact job name (NOT a glob; scancel has no "
    "pattern matching). Note this still hits a PEER's job of the same name unless the "
    "name carries your $SLURM_JOB_PREFIX.\n"
    "To sweep a name prefix, resolve it to ids first and eyeball them before cancelling "
    "(match the prefix literally, so a metacharacter in it cannot widen the match):\n"
    "  squeue -h -u \"$(whoami)\" -o '%i %j' | awk -v p='<prefix>' 'index($2, p)==1 {print $1}'"
)


def _tokenize(command: str) -> list[str]:
    """Split a shell command into tokens, keeping operators as their own tokens.

    Lexes line by line and emits an explicit ``\\n`` separator, because ``shlex`` with
    ``whitespace_split`` swallows newlines as ordinary whitespace — which would fold a
    whole multi-line script into one command and hide every ``scancel`` after line one.
    """
    tokens: list[str] = []
    for line in command.splitlines():
        lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        try:
            tokens.extend(lexer)
        except ValueError:
            # Unbalanced quotes — the shell would reject this anyway. Fall back to a
            # whitespace split so a malformed `scancel -u $USER` still can't sneak past.
            tokens.extend(line.split())
        tokens.append("\n")
    return tokens


def _split_segments(tokens: list[str]) -> list[list[str]]:
    """Group tokens into individual commands, split on shell operators."""
    segments: list[list[str]] = [[]]
    for token in tokens:
        if token not in OPERATORS:
            segments[-1].append(token)
            continue
        if token in REDIRECT_OPERATORS and segments[-1] and segments[-1][-1].isdigit():
            segments[-1].pop()  # a file descriptor (`2>`), not a job id
        segments.append([])
    return [segment for segment in segments if segment]


def _strip_wrappers(segment: list[str]) -> list[str]:
    """Peel leading env assignments, shell keywords and command wrappers off a segment.

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
        if head in PLAIN_WRAPPERS or head in SHELL_KEYWORDS:
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


def is_scoped(args: list[str], *, variables_are_targets: bool = True) -> bool:
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
        elif _is_job_id(token, variables_are_targets=variables_are_targets):
            return True
        index += 1
    return False


def _unscoped_in_segment(
    segment: list[str], *, variables_are_targets: bool
) -> list[list[str]]:
    """Unscoped cancels in one command, descending through any runner that wraps it.

    A command that merely mentions the word — ``rg "scancel -u" docs/`` — is left alone.
    Anything else whose head we don't recognise is scanned for a bare ``scancel`` token
    and analysed from there, so an unknown wrapper (``timeout 60 scancel --me``) fails
    CLOSED rather than being waved through.
    """
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
    if "scancel" in args[1:]:
        cancel_at = args.index("scancel")
        return _unscoped_in_segment(
            args[cancel_at:], variables_are_targets=variables_are_targets
        )
    return []


def _unscoped_in_runner(
    head: str, args: list[str], *, variables_are_targets: bool
) -> list[list[str]]:
    """Unscoped cancels inside a command that runs a command handed to it."""
    if head == "ssh":
        # `ssh ant-cluster scancel -u djrhails` — the remote command is the tail tokens.
        rest = _strip_wrapper_args(args, WRAPPER_VALUE_OPTS["ssh"], drop_host=True)
    else:
        rest = [token for token in args[1:] if not token.startswith("-")]
    if not rest:
        return []
    offenders = _unscoped_in_segment(rest, variables_are_targets=variables_are_targets)
    # `ssh ant-cluster "scancel -u djrhails"` — a quoted payload arrives as ONE token
    # carrying a whole command string, so re-lex it.
    for token in rest:
        if token != "scancel" and "scancel" in token:
            offenders.extend(unscoped_scancels(token))
    return offenders


def unscoped_scancels(command: str) -> list[list[str]]:
    """Every ``scancel`` invocation in ``command`` that fails to name its targets."""
    tokens = _tokenize(command)
    variables_are_targets = not any(
        PurePosixPath(token).name in QUERY_COMMANDS for token in tokens
    )
    offenders = []
    for segment in _split_segments(tokens):
        offenders.extend(
            _unscoped_in_segment(segment, variables_are_targets=variables_are_targets)
        )
    return offenders


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
