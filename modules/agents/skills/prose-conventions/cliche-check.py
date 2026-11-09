#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# ///
"""Detect LLM clichés in text files.

A port of the detection logic from Simon Willison's LLM cliché highlighter
(https://tools.simonwillison.net/llm-cliche-highlighter, source at
https://github.com/simonw/tools, Apache License 2.0). All 38 upstream patterns
are implemented; `--list` prints the inventory and `tests/test_cliche_check.py`
asserts parity against the recorded upstream ids.

This complements `prose-lint.sh`, which enforces the house style guide in
SKILL.md. The two overlap on vocabulary; this one exists to track an upstream
tool, so its patterns are transcribed rather than adapted.

Deliberate exception to the repo's verbose-regex convention: every pattern below
is transcribed character-for-character from upstream, and rewriting them in
`re.X` form (which requires escaping every literal space) would risk silent
transcription bugs in exactly the place where fidelity is the whole point. The
`name` field carries the explanation that inline comments normally would.
"""

from __future__ import annotations

import argparse
import re
import sys
from bisect import bisect_right
from collections.abc import Callable, Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path

WIKI_GROUP = "Signs of AI writing (Wikipedia)"
OWN_GROUP = "LLM clichés"

CHAIN_BODY = r"[^,.;:!?\n–—…]*"
CHAIN_SEP = (
    r"(?:\s*,\s*(?:and\s+|or\s+)?|\s+(?:and|or)\s+"
    r"|\s*[;&–—]\s*(?:and\s+|or\s+)?|\s+-{1,2}\s+)"
)

# Sentences opening on one of these repeat harmlessly; only content words count
# as anaphora.
ANAPHORA_SKIP = frozenset(
    """i it the a an this that we you they he she there but and so in as if my
    his her their its these those for at on of to is was""".split()
)


@dataclass(frozen=True, slots=True)
class Match:
    """One detected span, with an optional count badge for run-based finders."""

    start: int
    end: int
    badge: str | None = None
    badge_title: str | None = None


@dataclass(frozen=True, slots=True)
class Pattern:
    """A named detector. `find` maps text to the spans that matched it."""

    id: str
    name: str
    group: str
    find: Callable[[str], list[Match]]


Finder = Callable[[str], list[Match]]


def _regex_finder(pattern: str, *, ignore_case: bool = True) -> Finder:
    """Build a finder that reports every non-overlapping match of `pattern`."""
    compiled = re.compile(pattern, re.I if ignore_case else 0)

    def find(text: str) -> list[Match]:
        return [Match(m.start(), m.end()) for m in compiled.finditer(text)]

    return find


def _chain_finder(head: str, item_label: str) -> Finder:
    """Build a finder for runs of comma/and-joined clauses sharing a `head`.

    Args:
        head: Regex matching the repeated clause opener, e.g. ``no[-\\s]``.
        item_label: Singular noun for the badge tooltip, e.g. ``"no" item``.
    """
    item = head + CHAIN_BODY
    chain = re.compile(rf"\b{item}(?:{CHAIN_SEP}{item})+", re.I)
    head_test = re.compile(rf"^{head}", re.I)
    separator = re.compile(CHAIN_SEP, re.I)

    def find(text: str) -> list[Match]:
        found = []
        for m in chain.finditer(text):
            end = m.end()
            while end > m.start() and text[end - 1].isspace():
                end -= 1
            parts = separator.split(m.group(0))
            count = sum(1 for p in parts if head_test.match(p.strip()))
            plural = "" if count == 1 else "s"
            found.append(Match(m.start(), end, str(count), f"{count} {item_label}{plural}"))
        return found

    return find


def _grams(sentence: str, size: int) -> set[str]:
    """Return the set of lowercase word n-grams of length `size`."""
    words = re.findall(r"[a-z0-9'’-]+", sentence.lower())
    return {" ".join(words[i : i + size]) for i in range(len(words) - size + 1)}


@dataclass(frozen=True, slots=True)
class _Sentence:
    start: int
    end: int
    text: str


def _split_sentences(text: str, pattern: str, min_words: int) -> list[_Sentence]:
    """Split `text` into sentences of at least `min_words` whitespace tokens."""
    out = []
    for m in re.finditer(pattern, text):
        if len(m.group(0).split()) >= min_words:
            out.append(_Sentence(m.start(), m.end(), m.group(0)))
    return out


def _echo_finder(min_gram: int, min_run: int) -> Finder:
    """Build a finder for consecutive sentences repeating a shared word skeleton."""

    def shared_gram(a: _Sentence, b: _Sentence) -> str | None:
        common = _grams(a.text, min_gram) & _grams(b.text, min_gram)
        # Longest wins; the secondary sort only makes the badge deterministic.
        return min(common, key=lambda g: (-len(g), g)) if common else None

    def find(text: str) -> list[Match]:
        sents = _split_sentences(text, r"[^.!?\n]+[.!?]?", min_words=4)
        found: list[Match] = []
        i = 0
        while i < len(sents):
            j, shared = i, None
            while j + 1 < len(sents) and sents[j + 1].start - sents[j].end <= 3:
                gram = shared_gram(sents[j], sents[j + 1])
                if gram is None:
                    break
                shared = gram
                j += 1
            run = j - i + 1
            if run >= min_run and shared:
                end = sents[j].end
                while end > sents[i].start and text[end - 1].isspace():
                    end -= 1
                title = f"{run} sentences echoing “{shared}”"
                found.append(Match(sents[i].start, end, str(run), title))
                i = j + 1
            else:
                i += 1
        return found

    return find


def _question_chain_finder(min_run: int) -> Finder:
    """Build a finder for runs of consecutive question sentences."""
    chain = re.compile(r"[^.!?\n]+\?(?:\s+[^.!?\n]+\?)+")

    def find(text: str) -> list[Match]:
        found = []
        for m in chain.finditer(text):
            count = m.group(0).count("?")
            if count < min_run:
                continue
            start = m.start()
            while start < m.end() and text[start].isspace():
                start += 1
            found.append(Match(start, m.end(), str(count), f"{count} questions in a row"))
        return found

    return find


def _anaphora_finder(min_run: int) -> Finder:
    """Build a finder for runs of sentences opening on the same content word."""
    # A word starts with a letter, so a list marker (`- `) or a bold label's
    # asterisks never count as every bullet's shared opener.
    word = re.compile(r"[A-Za-z][A-Za-z'’-]*")

    def heads(text: str) -> list[tuple[int, int, str]]:
        out = []
        for m in re.finditer(r"[^.!?\n]+[.!?]", text):
            first = word.search(m.group(0))
            if first:
                out.append(
                    (m.start() + m.group(0).index(first.group(0)), m.end(), first.group(0).lower())
                )
        return out

    def find(text: str) -> list[Match]:
        sents = heads(text)
        found: list[Match] = []
        i = 0
        while i < len(sents):
            j = i
            while (
                j + 1 < len(sents)
                and sents[j + 1][2] == sents[i][2]
                and sents[j + 1][0] - sents[j][1] < 4
            ):
                j += 1
            run = j - i + 1
            if run >= min_run and sents[i][2] not in ANAPHORA_SKIP:
                title = f"{run} sentences opening “{sents[i][2]}”"
                found.append(Match(sents[i][0], sents[j][1], str(run), title))
                i = j + 1
            else:
                i += 1
        return found

    return find


def _own(pattern_id: str, name: str, regex: str, *, ignore_case: bool = True) -> Pattern:
    return Pattern(pattern_id, name, OWN_GROUP, _regex_finder(regex, ignore_case=ignore_case))


def _wiki(pattern_id: str, name: str, regex: str) -> Pattern:
    return Pattern(pattern_id, name, WIKI_GROUP, _regex_finder(regex))


PATTERNS: tuple[Pattern, ...] = (
    Pattern(
        "no-chain",
        "“No X, no Y” chains",
        OWN_GROUP,
        _chain_finder(r"no[-\s]", "“no” item"),
    ),
    _own(
        "whole",
        "“That’s the whole …”",
        r"\b(?:that|this)(?:['’]s|\s+(?:is|was))\s+the\s+whole\b(?:\s+\w+)?",
    ),
    Pattern(
        "did-not-chain",
        "“Did not X, did not Y” chains",
        OWN_GROUP,
        _chain_finder(r"(?:did\s+not|didn['’]t)\s", "“did not” item"),
    ),
    _own(
        "dont-verb-it",
        "“Don’t VERB it … VERB it”",
        r"\b(?:do\s+not|don['’]t)\s+(?:just\s+|simply\s+|merely\s+)?(\w+)"
        r"(?:\s+(?:of|about|at|on|for|with|to))?\s+it\b[^.!?\n]*?"
        r"[.!?;,:–—]['\"”’]*\s*(?:just\s+|simply\s+|merely\s+)?"
        r"\1(?:\s+(?:of|about|at|on|for|with|to))?\s+it\b",
    ),
    _own(
        "sit-with",
        "“Sit with that”",
        r"\bsit(?:s|ting)?\s+with\s+(?:that|this|it|(?:the|your)\s+"
        r"(?:discomfort|feelings?|tension|weight|uncertainty|ambiguity|grief|silence|unease))"
        r"\b(?:\s+for\s+a\s+\w+)?",
    ),
    _own(
        "already-know",
        "“You already know”",
        r"\byou\s+already\s+knows?\s+(?:the\s+answer|what|how|why|this|that|it|who|where)\b"
        r"|\byou\s+already\s+knows?\b(?![ \t]+\w)",
    ),
    _own(
        "is-the-entire",
        "“Is the entire …”",
        r"(?:\b(?:is|was|are|were)|['’]s)\s+the\s+entire\b(?:\s+\w+)?",
    ),
    _own(
        "the-entire-is",
        "“The entire … is”",
        r"\bthe\s+entire\s+[\w'’-]+(?:\s+[\w'’-]+){0,4}?\s+(?:is|was|are|were)\b",
    ),
    _own(
        "is-real",
        "“Is real … and / not”",
        r"\bis\s+(?:(?:the|a)\s+real\b(?![\s-]+(?:estate|time|life|world|quick)\b)"
        r"[^.!?\n]*?\b(?:and|not)\s+it\b"
        r"|real\b(?![\s-]+(?:estate|time|life|world|quick)\b)[^.!?\n]*?\b(?:and|not)\b)",
    ),
    _own(
        "punchline",
        "“The punchline is”",
        r"\bthe\s+punchline(?:\s+(?:is|was|being)\b|\s*[:?])",
    ),
    _own(
        "worth-naming",
        "“Worth naming”",
        r"(?:\b(?:is|are|was|were|feels?|felt|seems?|seemed)|['’]s)\s+"
        r"(?:\w+\s+){0,2}?worth\s+naming\b(?!\s+names\b)|\bworth\s+naming\s*:",
    ),
    _own(
        "not-nothing",
        "“That’s not nothing”",
        r"\b(?:that|this|it|which)(?:['’]s|\s+(?:is|was))\s+not\s+nothing\b",
    ),
    _own(
        "is-the-whole",
        "“Is the whole …”",
        r"(?:\b(?:is|was|are|were)|['’]s)\s+the\s+whole\b(?:\s+\w+)?"
        r"|\bhere(?:['’]s|\s+is)\s+the\s+whole\b(?:\s+\w+)?",
    ),
    Pattern("echo-triad", "Echoing sentence runs", OWN_GROUP, _echo_finder(4, 2)),
    _own(
        "performative-honesty",
        "Performative honesty",
        r"\bI\s+(?:will\s+not|won['’]t)\s+pretend\b"
        r"|\b(?:I['’]ll|let['’]s|to)\s+be\s+(?:honest|clear|blunt|real)\b"
        r"|(?:^|[.!?–—]\s+|\n)(?:Honestly|Look|Truthfully|Frankly)\s*,",
    ),
    _own(
        "thats-the-part",
        "“That’s the part …”",
        r"\b(?:that|this|it)(?:['’]s|\s+(?:is|was))\s+the\s+part\b"
        r"|\bthe\s+part\s+that\s+(?:makes|made|gets|got|keeps|kept)\s+(?:me|you|us|it)\b"
        r"|\bmy\s+favou?rite\s+part\s+of\b",
    ),
    _own(
        "the-only-i-trust",
        "“The only X I trust”",
        r"\bthe\s+only\s+[\w'’-]+(?:\s+[\w'’-]+){0,2}?\s+(?:I|you|we|it|he|she|they)\s+"
        r"(?:trust|need|needs|care|want|wants|use|uses|believe)\b"
        r"|\bthe\s+only\s+[\w'’-]+\s+that\s+(?:matters|counts|works|survives)\b",
    ),
    _own(
        "take-my-word",
        "“Don’t take my word for it”",
        r"\b(?:you\s+)?(?:do\s+not|don['’]t)\s+(?:have\s+to\s+)?take\s+my\s+word\s+for\s+"
        r"(?:it|any\s+of\s+(?:it|this|that))\b",
    ),
    _own(
        "turns-out",
        "“Turns out …”",
        r"(?:^|[.!?–—]\s+|\n)Turns\s+out\b|\bit\s+turns\s+out\s+that\b",
    ),
    _own(
        "fits-in-your-head",
        "“Fits in your head”",
        r"\b(?:hold|fit|fits|holds|held)\s+(?:it\s+)?in\s+your\s+head\b"
        r"|\bbatteries[-\s]included\b|\bit\s+just\s+works\b"
        r"|\bzero[-\s]config(?:uration)?\b|\bsane\s+defaults\b",
    ),
    Pattern(
        "stacked-questions",
        "Stacked rhetorical questions",
        OWN_GROUP,
        _question_chain_finder(2),
    ),
    Pattern("sentence-anaphora", "Repeated sentence openers", OWN_GROUP, _anaphora_finder(3)),
    _own(
        "colon-triple",
        "Colon into a triple",
        r":\s+[^.!?;:\n]{2,40},\s+[^.!?;:\n]{2,40},\s+(?:and\s+|or\s+)?[^.!?;:\n]{2,40}(?=[.!?\n])",
        ignore_case=False,
    ),
    _own(
        "heres-the-twist",
        "“Here’s the twist”",
        r"\bhere(?:['’]s|\s+is)\s+(?:the|a|my|one)\s+"
        r"(?:twist|thing|catch|kicker|rub|problem|first|second|third|next|recent|real|best"
        r"|worst|surprising|interesting|key|important)\b[\w\s-]{0,20}[:.]",
    ),
    _own("x-is-dead", "“X is dead”", r"\b[\w\s]{3,30}\s+(?:is|are)\s+dead\b|\blong\s+live\s+\w+"),
    _own(
        "thats-why-mattered",
        "“That’s why X mattered”",
        r"\b(?:that|this)(?:['’]s|\s+(?:is|was))\s+why\b[^.!?\n]{0,80}?"
        r"\b(?:matter(?:s|ed)?|count(?:s|ed)?)\b",
    ),
    _own(
        "stranded-auxiliary",
        "Stranded auxiliary contrast",
        r"[;:,]\s+[^.;:!?\n]{2,50}\s"
        r"(?:did|does|do|was|were|is|are|has|have|had|can|could|would|will)(?:n['’]t)?\s*[.;]"
        r"|\b(?:Maybe|Perhaps)\s+\w+[^.!?\n]{0,40}\s"
        r"(?:would|could|might|should|did|had|was|is)(?:n['’]t)?\s+(?:have\s*)?\.",
        ignore_case=False,
    ),
    _wiki(
        "ai-vocab",
        "AI vocabulary words",
        r"\b(?:delv(?:e|es|ed|ing)|tapestr(?:y|ies)|meticulous(?:ly)?|pivotal|intricate(?:ly)?"
        r"|intricacies|interplay|underscor(?:e|es|ed|ing)|garner(?:s|ed|ing)?"
        r"|bolster(?:s|ed|ing)?|vibrant|bustling|multifaceted|seamless(?:ly)?|commendable"
        r"|ever-evolving)\b",
    ),
    _wiki(
        "not-just",
        "“Not just X, but Y”",
        r"\bnot\s+(?:just|only|merely|simply)\s+[^.!?\n;]*?\bbut(?:\s+also)?\b"
        r"|\b(?:it|this|that)(?:['’]s|\s+(?:is|was))\s+not\s+[^.!?\n,;—–]{1,60}"
        r"[,;—–]\s*(?:it|this|that)(?:['’]s|\s+(?:is|was))\b",
    ),
    _wiki(
        "note-that",
        "“It’s important to note”",
        r"\bit(?:['’]s|\s+(?:is|was))\s+(?:also\s+)?"
        r"(?:important|worth|crucial|essential|vital)\s+"
        r"(?:to\s+(?:note|remember|understand|recognize|mention|pause|consider|ask)"
        r"|noting|mentioning|remembering|pausing|considering|asking)\b(?:\s+that\b)?"
        r"|\bit\s+should\s+be\s+noted\b",
    ),
    _wiki(
        "testament",
        "“Stands as a testament”",
        r"\b(?:stand|stands|stood|serve|serves|served|standing|serving)\s+as\s+(?:a|an)\s+"
        r"(?:\w+\s+)?(?:testament|reminder)\b"
        r"|\b(?:is|was|are|were|remain|remains)\s+a\s+(?:\w+\s+)?testament\s+to\b",
    ),
    _wiki(
        "crucial-role",
        "“Plays a crucial role”",
        r"\bplay(?:s|ed|ing)?\s+(?:a|an)\s+(?:\w+\s+)?"
        r"(?:crucial|pivotal|vital|key|significant|central|critical|important)\s+role\b",
    ),
    _wiki(
        "landscape",
        "“Ever-evolving landscape”",
        r"\b(?:ever-)?(?:evolving|changing|shifting)\s+landscape\b"
        r"|\bin\s+today['’]s\s+"
        r"(?:fast-paced|ever-changing|ever-evolving|digital|modern|competitive)\s+\w+",
    ),
    _wiki(
        "vague-experts",
        "“Experts argue”",
        r"\b(?:many|some|several|most|numerous)?\s*"
        r"(?:experts|critics|observers|scholars|analysts|commentators)\s+"
        r"(?:have\s+|often\s+|widely\s+)?"
        r"(?:argu(?:e|es|ed)|not(?:e|es|ed)|suggest(?:s|ed)?|believ(?:e|es|ed)|agree[ds]?"
        r"|contend(?:s|ed)?|observ(?:e|es|ed)|caution(?:s|ed)?|claim(?:s|ed)?|cit(?:e|es|ed)"
        r"|point(?:s|ed)?\s+out)\b"
        r"|\bindustry\s+reports?\s+(?:suggest|indicate|show)\w*\b",
    ),
    _wiki(
        "despite-challenges",
        "“Despite these challenges”",
        r"\bdespite\s+(?:these|those|such|its|their|the|numerous|significant|ongoing)\s+"
        r"(?:\w+\s+)?challenges\b"
        r"|\bfac(?:e|es|ed|ing)\s+(?:several|numerous|many|significant|various|a\s+number\s+of)"
        r"\s+challenges\b"
        r"|\bchallenges\s+remain\b|\bremains\s+to\s+be\s+seen\b|\b(?:only\s+)?time\s+will\s+tell\b",
    ),
    _wiki(
        "participle-tail",
        "Participle sentence tails",
        r",\s+(?:highlighting|underscoring|emphasizing|showcasing|reflecting|demonstrating"
        r"|illustrating|signaling|solidifying|cementing|reinforcing|underlining)\s+"
        r"(?:its|his|her|their|our|the|a|an|how|that|what|both)\b[^.!?\n]*",
    ),
    _wiki(
        "promo",
        "Promotional boilerplate",
        r"\bnestled\s+(?:in|on|among|between|along|at)\b|\bin\s+the\s+heart\s+of\b"
        r"|\brich\s+(?:cultural\s+|historical\s+)?(?:heritage|history|tapestry)\b"
        r"|\bhidden\s+gem\b|\bmust-(?:visit|see|try)\b|\bbreathtaking\b"
        r"|\bboasts?\s+(?:a|an|the)\b|\bstunning\s+(?:views?|scenery|architecture|backdrop)\b",
    ),
    _wiki(
        "ai-leftovers",
        "Chatbot leftovers",
        r"\bas\s+an\s+ai(?:\s+language)?\s+model\b|\bas\s+of\s+my\s+last\s+(?:update|training)\b"
        r"|\bknowledge\s+cutoff\b"
        r"|\bI\s+(?:cannot|can['’]t|do\s+not|don['’]t)\s+"
        r"(?:browse\s+the\s+internet|access\s+real-?time)\b"
        r"|contentReference|oaicite|turn0(?:search|news|image)\d*|attributableIndex|utm_source=",
    ),
)


CONTEXT_WORDS = 12
SENTENCE_END = frozenset(".!?…")
TRAILING_CLOSERS = frozenset("\"'”’)]")


@dataclass(frozen=True, slots=True)
class Found:
    """A match paired with the pattern that produced it."""

    start: int
    end: int
    pattern: Pattern
    badge: str | None


@dataclass(slots=True)
class Region:
    """A sentence, or run of merged sentences, containing matches."""

    start: int
    end: int
    found: list[Found]


@dataclass(slots=True)
class Window:
    """A region widened by `CONTEXT_WORDS` either side, merged where adjacent."""

    start: int
    end: int
    regions: list[Region]


@dataclass(frozen=True, slots=True)
class Hit:
    """A surviving match located in a specific file, line and sentence."""

    path: Path
    line: int
    pattern: Pattern
    text: str
    badge: str | None
    sentence: str


def collect_matches(text: str, patterns: Sequence[Pattern]) -> tuple[list[Found], dict[str, int]]:
    """Gather matches from every pattern, dropping any an earlier match covers.

    Matches sort by start ascending then end descending, so at a shared start
    the longest wins, and anything beginning before the previous match ended is
    dropped. This is what stops `pivotal` being reported separately inside
    `plays a pivotal role`.

    Returns:
        The surviving matches in document order, and a per-pattern hit count.
    """
    per_pattern = {p.id: 0 for p in PATTERNS}
    raw = [Found(m.start, m.end, p, m.badge) for p in patterns for m in p.find(text)]
    raw.sort(key=lambda f: (f.start, -f.end))
    kept: list[Found] = []
    for found in raw:
        if kept and found.start < kept[-1].end:
            continue
        kept.append(found)
        per_pattern[found.pattern.id] += 1
    return kept, per_pattern


def sentence_bounds(text: str, start: int, end: int) -> tuple[int, int]:
    """Widen a span to the sentence containing it, trailing quotes included."""
    left = start
    while left > 0 and text[left - 1] not in SENTENCE_END and text[left - 1] != "\n":
        left -= 1
    while left < start and text[left].isspace():
        left += 1
    right = end
    while right < len(text):
        char = text[right]
        if char == "\n":
            break
        right += 1
        if char in SENTENCE_END:
            while right < len(text) and text[right] in TRAILING_CLOSERS:
                right += 1
            break
    return left, right


def build_regions(text: str, matches: Sequence[Found]) -> list[Region]:
    """Expand each match to its sentence, merging sentences that touch."""
    regions: list[Region] = []
    for match in matches:
        start, end = sentence_bounds(text, match.start, match.end)
        if regions and start <= regions[-1].end:
            regions[-1].end = max(regions[-1].end, end)
            regions[-1].found.append(match)
        else:
            regions.append(Region(start, end, [match]))
    return regions


def _expand_left(text: str, pos: int, words: int) -> int:
    index, seen = pos, 0
    while index > 0 and seen < words:
        while index > 0 and text[index - 1].isspace():
            index -= 1
        if index == 0:
            break
        while index > 0 and not text[index - 1].isspace():
            index -= 1
        seen += 1
    return index


def _expand_right(text: str, pos: int, words: int) -> int:
    index, seen, size = pos, 0, len(text)
    while index < size and seen < words:
        while index < size and text[index].isspace():
            index += 1
        if index == size:
            break
        while index < size and not text[index].isspace():
            index += 1
        seen += 1
    return index


def build_windows(text: str, regions: Sequence[Region]) -> list[Window]:
    """Pad each region by `CONTEXT_WORDS` words, merging windows that meet."""
    windows: list[Window] = []
    for region in regions:
        start = _expand_left(text, region.start, CONTEXT_WORDS)
        end = _expand_right(text, region.end, CONTEXT_WORDS)
        last = windows[-1] if windows else None
        if last and (start <= last.end or not text[last.end : start].split()):
            last.end = max(last.end, end)
            last.regions.append(region)
        else:
            windows.append(Window(start, end, [region]))
    return windows


def _line_starts(text: str) -> list[int]:
    return [0] + [i + 1 for i, ch in enumerate(text) if ch == "\n"]


def scan(text: str, path: Path, patterns: Sequence[Pattern]) -> Iterator[Hit]:
    """Yield the surviving hits in document order, each with its sentence."""
    starts = _line_starts(text)
    matches, _ = collect_matches(text, patterns)
    for found in matches:
        left, right = sentence_bounds(text, found.start, found.end)
        yield Hit(
            path,
            bisect_right(starts, found.start),
            found.pattern,
            " ".join(text[found.start : found.end].split()),
            found.badge,
            " ".join(text[left:right].split()),
        )


def _select(only: list[str] | None, skip: list[str]) -> tuple[Pattern, ...]:
    unknown = sorted(set(only or []).union(skip) - {p.id for p in PATTERNS})
    if unknown:
        raise ValueError(f"unknown pattern id(s): {', '.join(unknown)}; see --list")
    chosen =PATTERNS if not only else tuple(p for p in PATTERNS if p.id in set(only))
    return tuple(p for p in chosen if p.id not in set(skip))


def _report(hit: Hit, *, colour: bool, context: str) -> str:
    badge = f" [{hit.badge}]" if hit.badge else ""
    label = f"[{hit.pattern.id}]"
    body = hit.sentence if context == "sentence" else hit.text
    body = body if len(body) <= 160 else body[:157] + "..."
    where = f"{hit.path}:{hit.line}"
    if not colour:
        return f"{label:<24} {body}{badge}  {where}"
    return f"\033[0;33m{label:<24}\033[0m \033[0;31m{body}{badge}\033[0m  \033[0;36m{where}\033[0m"


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("files", nargs="*", type=Path, help="text files to scan")
    parser.add_argument("--list", action="store_true", help="print the pattern inventory and exit")
    parser.add_argument("--only", action="append", metavar="ID", help="run only this pattern id")
    parser.add_argument("--skip", action="append", default=[], metavar="ID", help="disable an id")
    parser.add_argument("--no-colour", action="store_true", help="plain output")
    parser.add_argument(
        "--context",
        choices=("span", "sentence"),
        default="span",
        help="print the matched span (default) or the sentence containing it",
    )
    parser.add_argument(
        "--windows",
        action="store_true",
        help="print merged ±12-word context blocks instead of one line per hit",
    )
    parser.add_argument("--stats", action="store_true", help="print per-pattern hit counts")
    return parser.parse_args(argv)


def _print_windows(text: str, path: Path, patterns: Sequence[Pattern]) -> None:
    """Print the merged context blocks that back the tool's highlights-only view."""
    matches, _ = collect_matches(text, patterns)
    for window in build_windows(text, build_regions(text, matches)):
        ids = sorted({f.pattern.id for r in window.regions for f in r.found})
        print(f"--- {path} [{', '.join(ids)}]")
        print(" ".join(text[window.start : window.end].split()))
        print()


def main(argv: Sequence[str] | None = None) -> int:
    """Scan the given files and return 1 if any cliché was found."""
    args = _parse_args(sys.argv[1:] if argv is None else argv)

    if args.list:
        for pattern in PATTERNS:
            print(f"{pattern.id:<22} {pattern.group:<32} {pattern.name}")
        print(f"\n{len(PATTERNS)} patterns")
        return 0

    if not args.files:
        print("Usage: cliche-check.py <file ...>", file=sys.stderr)
        return 2

    try:
        patterns = _select(args.only, args.skip)
    except ValueError as err:
        print(f"cliche-check: {err}", file=sys.stderr)
        return 2
    colour = not args.no_colour and sys.stdout.isatty()
    hits: list[Hit] = []
    totals: dict[str, int] = {p.id: 0 for p in PATTERNS}
    for path in args.files:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as err:
            print(f"cliche-check: cannot read {path}: {err}", file=sys.stderr)
            return 2
        if args.windows:
            _print_windows(text, path, patterns)
        hits.extend(scan(text, path, patterns))
        for pattern_id, count in collect_matches(text, patterns)[1].items():
            totals[pattern_id] += count

    if not args.windows:
        for hit in sorted(hits, key=lambda h: (str(h.path), h.line)):
            print(_report(hit, colour=colour, context=args.context))

    if args.stats:
        print()
        for pattern_id, count in sorted(totals.items(), key=lambda kv: (-kv[1], kv[0])):
            if count:
                print(f"{count:>4}  {pattern_id}")

    print()
    if not hits:
        print("No clichés detected.")
        return 0
    print(f"Found {len(hits)} cliché(s) across {len({h.pattern.id for h in hits})} pattern(s).")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
