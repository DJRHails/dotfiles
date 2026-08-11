"""Shared shell-command walking for the PreToolUse guard hooks.

A guard hook has to answer "does this Bash command *run* X?" — and the honest answer needs a
lexer, not a regex. ``rg "scancel" docs/`` and ``ssh host "pkill -f foo"`` differ only in
whether the quoted text is data or a command, which is exactly what a regex cannot see.

Extracted from ``block_unscoped_scancel.py``, which grew this parser first. It lives here so the
second guard (``block_self_matching_pkill``) reuses one tokeniser instead of carrying a divergent
copy — two parsers disagreeing about what counts as a command is how one guard ends up with a hole
the other does not. Both guards' behaviour suites pin what is here, so run BOTH after a change.

The shared contract for callers: peel wrappers with :func:`strip_wrappers`, then treat an
unrecognised head as *possibly* running its arguments and fail CLOSED. Only
:data:`MENTION_ONLY_COMMANDS` and :data:`LOOKUP_COMMANDS` provably cannot.
"""

from __future__ import annotations

import shlex

# Wrappers whose first bare operand is a VALUE, not the wrapped command: `timeout 60 …`,
# `flock /tmp/lock …`. Peeling only the wrapper name left `60` as the head, which matched
# nothing and put the real command out of the parser's reach.
OPERAND_WRAPPERS = frozenset({"timeout", "flock"})

# Wrappers to peel off before deciding what the real command is. Not exhaustive, and it does not
# need to be: an unrecognised head falls through to the caller's fail-closed scan. `xargs` takes
# value-options, so it is handled separately below. OPERAND_WRAPPERS is unioned in rather than
# listed again, because strip_wrappers only consults it inside this set's branch: an operand
# wrapper missing from here would silently never peel, and the guard would fail open invisibly.
PLAIN_WRAPPERS = OPERAND_WRAPPERS | frozenset(
    {
        "sudo", "doas", "time", "nohup", "command", "exec", "builtin", "env",
        "nice", "ionice", "stdbuf", "setsid", "watch",
    }
)  # fmt: skip

# Shell keywords that can head a segment once it is split on `;`, so the real command follows
# them: `if …; then pkill -f foo; fi`. The loop and conditional openers/closers are here too:
# leaving `while` unpeelable hid everything behind it (`while ssh host "pkill -f x"` — the
# `ssh` was never recognised as a runner, so the quoted payload fell to a bare-token scan).
# `block_self_matching_pkill` also reads this set to tell command position from data, so dropping
# a keyword here quietly widens what its loop detection reads as prose.
SHELL_KEYWORDS = frozenset(
    {
        "then", "do", "else", "elif", "{", "}", "!", "--",
        "if", "fi", "while", "until", "for", "done",
    }
)  # fmt: skip

# Commands whose arguments are DATA, not commands — they can only ever *mention* a command.
# Listing them keeps `rg 'pkill -f' docs/` out of the fail-closed scan; a missing entry
# over-blocks, which is the direction to err in.
MENTION_ONLY_COMMANDS = frozenset(
    {
        "rg", "grep", "egrep", "fgrep", "ag", "ack", "echo", "printf", "cat", "sed",
        "awk", "head", "tail", "less", "more", "diff", "man", "comm", "sort", "uniq",
    }
)  # fmt: skip

# Flags whose value is free TEXT by the flag's own contract — a commit message, a PR title, a
# search pattern. Text handed to one of these cannot execute, so a guard must not read a command
# name inside it as an invocation. Without the exemption the guards block their own paperwork —
# a `git commit -m` whose message merely discusses a cancel was refused, which is how a guard
# teaches people to route around it. (Heredoc-fed messages are still blocked: the lexer reads
# heredoc lines as commands. `git commit -F <file>` is the shape that always works.)
FREE_TEXT_OPTS = frozenset(
    {
        "-m", "--message", "-F", "--file", "--body", "--body-file", "-t", "--title",
        "-d", "--description", "--notes", "--subject", "--grep",
    }
)  # fmt: skip

# The only command heads these flags are trusted on. On an arbitrary unrecognised head the
# "value" after one of these short flags can BE the command — tmux's `-d` takes no value, so
# `tmux new-session -d 'pkill -f x'` would have its whole payload dropped as prose. git and gh
# are paperwork: their -m/-F/--title values are messages by contract, never executed.
FREE_TEXT_COMMANDS = frozenset({"git", "gh"})

# Commands that ask WHERE a command lives rather than running it. Without these, the fail-closed
# scan blocks `which pkill` — which is what an agent reaches for while working out why it just
# got blocked, so the guard would obstruct its own diagnosis.
LOOKUP_COMMANDS = frozenset({"which", "type", "whereis", "hash"})

# Commands that execute a command string handed to them, so a quoted command inside their
# arguments is a real invocation — `ssh host "pkill -f foo"` really does pkill.
COMMAND_RUNNERS = frozenset({"ssh", "bash", "sh", "zsh", "dash", "eval"})

# Wrapper options that consume the next token, so the wrapper's own flags are not mistaken for
# the wrapped command.
WRAPPER_VALUE_OPTS = {
    "xargs": frozenset({"-a", "-d", "-E", "-I", "-i", "-L", "-l", "-n", "-P", "-s", "--replace"}),
    # ssh's value-taking flags; the first bare token after them is the host.
    "ssh": frozenset({"-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l",
                      "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w"}),
}  # fmt: skip

# Operators that redirect rather than separate. They still end a command, but the token before
# them may be a file-descriptor number (`2>/dev/null`), which must not be read as an operand.
REDIRECT_OPERATORS = frozenset({"<", ">", ">>", "<<", "<<<", ">&", "<&", "&>", ">|"})

# `shlex` has already discarded adjacency by the time we segment, so `1937678 >` and `2>` look
# identical. Only a single digit that could really BE a descriptor is dropped — treating every
# trailing digit run as one ate real operands.
FD_DIGITS = frozenset({"0", "1", "2"})

# Shell operators that separate one command from the next. `shlex` with punctuation_chars emits
# these as standalone tokens; `\n` is inserted by `tokenize`, which lexes line by line (shlex
# treats a newline as ordinary whitespace).
OPERATORS = frozenset({"|", "||", "&", "&&", ";", ";;", "|&", "(", ")", "\n"}) | REDIRECT_OPERATORS

# The characters `shlex` treats as punctuation. It merges ADJACENT punctuation into one token, so
# `);` arrives as a single `");"` that matches no operator — which stops `split_segments`
# splitting there and glues a whole trailing command onto the segment inside a `$(…)`.
# `split_operator_run` takes such a run apart again.
PUNCTUATION_CHARS = frozenset("();<>|&")

# Longest operator first, so `&&` is not read as two `&` and `<<<` not as `<<` plus `<`.
MAX_OPERATOR_LENGTH = 3


def tokenize(command: str) -> list[str]:
    """Split a shell command into tokens, keeping operators as their own tokens.

    Lexes line by line and emits an explicit ``\\n`` separator, because ``shlex`` with
    ``whitespace_split`` swallows newlines as ordinary whitespace — which would fold a whole
    multi-line script into one command and hide every invocation after line one.
    """
    tokens: list[str] = []
    for line in command.splitlines():
        lexer = shlex.shlex(line, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        try:
            lexed = list(lexer)
        except ValueError:
            # Unbalanced quotes — the shell would reject this anyway. Fall back to a whitespace
            # split so a malformed command still cannot sneak past.
            lexed = line.split()
        for token in lexed:
            tokens.extend(split_operator_run(token))
        tokens.append("\n")
    return tokens


def split_operator_run(token: str) -> list[str]:
    """Take a merged run of punctuation apart into the operators it spells.

    ``shlex`` hands back ``");"`` as one token, which is in no operator set and so separates
    nothing. Returns ``[token]`` unchanged for anything that is not purely punctuation, or that
    does not decompose cleanly into known operators.
    """
    if not token or not all(char in PUNCTUATION_CHARS for char in token):
        return [token]
    parts: list[str] = []
    index = 0
    while index < len(token):
        for length in range(MAX_OPERATOR_LENGTH, 0, -1):
            candidate = token[index : index + length]
            if candidate in OPERATORS:
                parts.append(candidate)
                index += length
                break
        else:
            return [token]  # an unknown punctuation run: leave it for the caller to see
    return parts


def split_segments(tokens: list[str]) -> list[list[str]]:
    """Group tokens into individual commands, split on shell operators."""
    segments: list[list[str]] = [[]]
    for token in tokens:
        if token not in OPERATORS:
            segments[-1].append(token)
            continue
        if token in REDIRECT_OPERATORS and segments[-1] and segments[-1][-1] in FD_DIGITS:
            segments[-1].pop()  # a file descriptor (`2>`), not an operand
        segments.append([])
    return [segment for segment in segments if segment]


def strip_wrappers(segment: list[str]) -> list[str]:
    """Peel leading env assignments, shell keywords and command wrappers off a segment.

    Returns the tokens of the command actually being run, so `xargs -r pkill` and
    `ssh host pkill …` both reduce to a `pkill …` head.
    """
    tokens = list(segment)
    while tokens:
        head = tokens[0]
        if "=" in head and not head.startswith("-") and head.split("=", 1)[0].isidentifier():
            tokens.pop(0)  # VAR=value prefix
            continue
        if head in PLAIN_WRAPPERS or head in SHELL_KEYWORDS:
            if head in OPERAND_WRAPPERS:
                # drop the wrapper, then its own flags, then its value operand
                tokens = strip_wrapper_args(tokens, frozenset(), drop_host=True)
            else:
                tokens.pop(0)
            continue
        if head == "xargs":
            tokens = strip_wrapper_args(tokens, WRAPPER_VALUE_OPTS["xargs"], drop_host=False)
            continue
        break
    return tokens


def drop_free_text_values(tokens: list[str]) -> list[str]:
    """Remove values that a :data:`FREE_TEXT_OPTS` flag claims, so prose is not read as commands.

    ``--title "block pkill -f"`` leaves ``--title`` in place and drops the string after it. Also
    handles the ``--flag=value`` spelling, whose value never was a separate token.

    Callers must apply this only when the command head is in :data:`FREE_TEXT_COMMANDS`: the
    flags are trusted by the *head's* contract, not their own spelling — on an unknown head,
    ``-d``'s "value" can be the command itself (``tmux new-session -d 'pkill -f x'``).

    Only the *immediately following* token is dropped. A flag that takes free text takes exactly
    one operand, so consuming more would hide a real command: ``git commit -m "msg" && pkill -f x``
    must still be caught, and it is, because the walker has already split on ``&&``.
    """
    kept: list[str] = []
    skip_next = False
    for token in tokens:
        if skip_next:
            skip_next = False
            continue
        if token in FREE_TEXT_OPTS:
            kept.append(token)
            skip_next = True
            continue
        if token.startswith("--") and "=" in token and token.split("=", 1)[0] in FREE_TEXT_OPTS:
            kept.append(token.split("=", 1)[0])
            continue
        kept.append(token)
    return kept


def strip_runner_args(head: str, tokens: list[str]) -> list[str]:
    """Drop a command runner, its own flags, and — for ssh — the destination host.

    Both guards descend into runners through here, so they cannot drift on which runners take
    value options or on which of them puts a destination ahead of the command it runs.
    """
    return strip_wrapper_args(
        tokens, WRAPPER_VALUE_OPTS.get(head, frozenset()), drop_host=head == "ssh"
    )


def strip_wrapper_args(
    tokens: list[str], value_opts: frozenset[str], *, drop_host: bool
) -> list[str]:
    """Drop a wrapper (tokens[0]), its options, and optionally its first bare operand.

    ``drop_host`` drops that operand too, for the wrappers whose first operand is a value rather
    than the start of the wrapped command: ssh's destination, timeout's duration, flock's path.
    """
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
