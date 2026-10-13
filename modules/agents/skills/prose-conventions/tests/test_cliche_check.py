"""Parity tests for cliche-check.py against the upstream LLM cliché highlighter.

`UPSTREAM_IDS` is the pattern inventory recorded from
https://github.com/simonw/tools/blob/main/llm-cliche-highlighter.html on
2026-08-30. Refresh it by re-fetching that file and re-reading the `id:` keys of
its `patterns` array; a diff against this list is the parity check.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

_SOURCE = Path(__file__).resolve().parent.parent / "cliche-check.py"
_SPEC = importlib.util.spec_from_file_location("cliche_check", _SOURCE)
assert _SPEC and _SPEC.loader
cc = importlib.util.module_from_spec(_SPEC)
# Register before executing: @dataclass resolves cls.__module__ through
# sys.modules, and fails with an opaque AttributeError if the name is missing.
sys.modules[_SPEC.name] = cc
_SPEC.loader.exec_module(cc)

UPSTREAM_IDS = [
    "no-chain",
    "whole",
    "did-not-chain",
    "dont-verb-it",
    "sit-with",
    "already-know",
    "is-the-entire",
    "the-entire-is",
    "is-real",
    "punchline",
    "worth-naming",
    "not-nothing",
    "is-the-whole",
    "echo-triad",
    "performative-honesty",
    "thats-the-part",
    "the-only-i-trust",
    "take-my-word",
    "turns-out",
    "fits-in-your-head",
    "stacked-questions",
    "sentence-anaphora",
    "colon-triple",
    "heres-the-twist",
    "x-is-dead",
    "thats-why-mattered",
    "stranded-auxiliary",
    "ai-vocab",
    "not-just",
    "note-that",
    "testament",
    "crucial-role",
    "landscape",
    "vague-experts",
    "despite-challenges",
    "participle-tail",
    "promo",
    "ai-leftovers",
]

# One example per pattern that must trigger it. These double as documentation of
# what each id actually catches.
POSITIVES = {
    "no-chain": "No fluff, no filler, no jargon.",
    "whole": "That's the whole point.",
    "did-not-chain": "It did not crash, did not leak, did not stall.",
    "dont-verb-it": "Don't just read it, read it properly.",
    "sit-with": "Sit with that.",
    "already-know": "You already know the answer.",
    "is-the-entire": "That is the entire point.",
    "the-entire-is": "The entire premise is wrong.",
    "is-real": "The risk is real and it matters.",
    "punchline": "The punchline is that it worked.",
    "worth-naming": "That is worth naming.",
    "not-nothing": "That's not nothing.",
    "is-the-whole": "That is the whole story.",
    "echo-triad": "The model learns the shape of the data. The model learns the shape of the task.",
    "performative-honesty": "Honestly, it did not work.",
    "thats-the-part": "That's the part I remember.",
    "the-only-i-trust": "The only benchmark I trust is this one.",
    "take-my-word": "Don't take my word for it.",
    "turns-out": "Turns out it was cached.",
    "fits-in-your-head": "It fits in your head.",
    "stacked-questions": "Why does it matter? Who benefits?",
    "sentence-anaphora": "Maybe it works. Maybe it doesn't. Maybe nobody cares.",
    "colon-triple": "It offers three things: speed, clarity, and scale.",
    "heres-the-twist": "Here's the twist: it was cached all along.",
    "x-is-dead": "The framework is dead.",
    "thats-why-mattered": "That's why the result mattered.",
    "stranded-auxiliary": "It shipped, the tests did.",
    "ai-vocab": "We delve into the tapestry.",
    "not-just": "It's not just fast, it's correct.",
    "note-that": "It's important to note that this is slow.",
    "testament": "It stands as a testament to the design.",
    "crucial-role": "Caching plays a crucial role here.",
    "landscape": "The ever-evolving landscape of tooling.",
    "vague-experts": "Experts argue that it scales.",
    "despite-challenges": "Despite these challenges, it shipped.",
    "participle-tail": "It shipped on time, highlighting the team's discipline.",
    "promo": "The hotel is nestled in the hills.",
    "ai-leftovers": "As an AI language model, I cannot browse the internet.",
}

# Guards that upstream encodes as lookaheads or skip-lists. If a port drops one,
# the pattern still fires on POSITIVES but starts flagging ordinary prose, so
# these are the tests that actually catch a bad transcription.
NEGATIVES = {
    "is-real": "This is real estate and property law.",
    "sentence-anaphora": "The cat sat. The dog ran. The bird flew.",
    "worth-naming": "He is worth naming names over.",
    "stacked-questions": "Why does it matter? It matters because it ships.",
    "echo-triad": "The model learns quickly. Deployment happened on Tuesday.",
}


def _find(pattern_id: str, text: str) -> list:
    pattern = next(p for p in cc.PATTERNS if p.id == pattern_id)
    return pattern.find(text)


def test_every_upstream_pattern_is_implemented():
    assert [p.id for p in cc.PATTERNS] == UPSTREAM_IDS


def test_no_duplicate_pattern_ids():
    ids = [p.id for p in cc.PATTERNS]
    assert len(ids) == len(set(ids))


def test_every_pattern_has_a_positive_example():
    assert set(POSITIVES) == set(UPSTREAM_IDS)


@pytest.mark.parametrize("pattern_id", UPSTREAM_IDS)
def test_pattern_fires_on_its_example(pattern_id):
    assert _find(pattern_id, POSITIVES[pattern_id]), f"{pattern_id} did not fire"


@pytest.mark.parametrize("pattern_id", sorted(NEGATIVES))
def test_pattern_respects_its_guard(pattern_id):
    assert not _find(pattern_id, NEGATIVES[pattern_id]), f"{pattern_id} false-positived"


def test_chain_finder_counts_items():
    matches = _find("no-chain", "No fluff, no filler, no jargon.")
    assert matches[0].badge == "3"


def test_question_chain_counts_questions():
    matches = _find("stacked-questions", "Why? How? When?")
    assert matches[0].badge == "3"


def test_anaphora_counts_sentences():
    matches = _find("sentence-anaphora", "Maybe a. Maybe b. Maybe c. Maybe d.")
    assert matches[0].badge == "4"


def test_anaphora_ignores_list_markers():
    bullets = "- **Kept:** the old rule.\n- **Dropped:** the new one.\n- **Unchanged:** the rest.\n"
    assert not _find("sentence-anaphora", bullets)


def test_anaphora_still_fires_inside_a_list():
    bullets = "- Maybe it works.\n- Maybe it doesn't.\n- Maybe nobody cares.\n"
    assert _find("sentence-anaphora", bullets)


def test_scan_reports_line_numbers(tmp_path):
    target = tmp_path / "doc.md"
    target.write_text("clean line\n\nThat's not nothing.\n", encoding="utf-8")
    hits = list(cc.scan(target.read_text(encoding="utf-8"), target, cc.PATTERNS))
    assert [h.line for h in hits if h.pattern.id == "not-nothing"] == [3]


def test_clean_text_produces_no_hits():
    text = "The cache stores 1.5KB per entry. Lookups take 40 microseconds.\n"
    assert not list(cc.scan(text, Path("x.md"), cc.PATTERNS))


def test_exit_code_is_nonzero_on_hits(tmp_path, capsys):
    target = tmp_path / "doc.md"
    target.write_text("That's not nothing.\n", encoding="utf-8")
    assert cc.main([str(target), "--no-colour"]) == 1
    assert "not-nothing" in capsys.readouterr().out


def test_exit_code_is_zero_on_clean_file(tmp_path):
    target = tmp_path / "doc.md"
    target.write_text("The cache stores 1.5KB per entry.\n", encoding="utf-8")
    assert cc.main([str(target), "--no-colour"]) == 0


def test_only_and_skip_select_patterns():
    assert [p.id for p in cc._select(["not-nothing"], [])] == ["not-nothing"]
    assert "not-nothing" not in [p.id for p in cc._select(None, ["not-nothing"])]


def test_undecodable_file_is_an_error_not_a_finding(tmp_path, capsys):
    target = tmp_path / "latin1.md"
    target.write_bytes(b"caf\xe9\n")
    assert cc.main([str(target), "--no-colour"]) == 2
    assert "cannot read" in capsys.readouterr().err


@pytest.mark.parametrize("flag", ["--only", "--skip"])
def test_unknown_pattern_id_is_an_error(tmp_path, capsys, flag):
    target = tmp_path / "doc.md"
    target.write_text("That's not nothing.\n", encoding="utf-8")
    assert cc.main([str(target), flag, "not-nothin", "--no-colour"]) == 2
    assert "not-nothin" in capsys.readouterr().err
