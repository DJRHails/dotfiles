"""Parity checks against fixtures captured from the upstream highlighter.

See `fixtures/README.md` for provenance and how to refresh. These tests are the
reason to trust the port: `test_cliche_check.py` checks our own expectations,
this file checks upstream's.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

_SOURCE = Path(__file__).resolve().parent.parent / "cliche-check.py"
_SPEC = importlib.util.spec_from_file_location("cliche_check", _SOURCE)
assert _SPEC and _SPEC.loader
cc = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = cc
_SPEC.loader.exec_module(cc)

_FIXTURES = Path(__file__).resolve().parent / "fixtures"
CASES = json.loads((_FIXTURES / "upstream_pattern_cases.json").read_text(encoding="utf-8"))
GOLDEN = json.loads((_FIXTURES / "upstream_pipeline_golden.json").read_text(encoding="utf-8"))
TEXT = GOLDEN["text"]

_BY_ID = {p.id: p for p in cc.PATTERNS}


def _case_id(case: list) -> str:
    sample = " ".join(case[1].split())
    return f"{case[0]}::{sample[:40]}"


def test_corpus_covers_every_pattern():
    assert {case[0] for case in CASES} == {p.id for p in cc.PATTERNS}


@pytest.mark.parametrize("case", CASES, ids=_case_id)
def test_finder_matches_upstream_expectation(case):
    """Each finder returns the match count, and badges, upstream records."""
    pattern_id, sample, want_count = case[0], case[1], case[2]
    got = _BY_ID[pattern_id].find(sample)
    assert len(got) == want_count
    if len(case) > 3:
        assert [int(m.badge) for m in got if m.badge is not None] == case[3]


def _pipeline():
    matches, per_pattern = cc.collect_matches(TEXT, cc.PATTERNS)
    regions = cc.build_regions(TEXT, matches)
    return matches, per_pattern, regions, cc.build_windows(TEXT, regions)


def test_overlap_suppression_matches_upstream():
    """The surviving spans, in order, are identical after suppression."""
    matches, _, _, _ = _pipeline()
    want = [(m["start"], m["end"], m["patternId"], m["badge"]) for m in GOLDEN["matches"]]
    assert [(f.start, f.end, f.pattern.id, f.badge) for f in matches] == want


def test_suppression_actually_discards_something():
    """Guards the test above: without suppression the counts would differ."""
    unsuppressed = sum(len(p.find(TEXT)) for p in cc.PATTERNS)
    assert unsuppressed > len(GOLDEN["matches"])


def test_sentence_regions_match_upstream():
    _, _, regions, _ = _pipeline()
    want = [(r["start"], r["end"], r["n"]) for r in GOLDEN["regions"]]
    assert [(r.start, r.end, len(r.found)) for r in regions] == want


def test_context_windows_match_upstream():
    _, _, _, windows = _pipeline()
    want = [(w["start"], w["end"], w["n"]) for w in GOLDEN["windows"]]
    assert [(w.start, w.end, len(w.regions)) for w in windows] == want


def test_per_pattern_counts_match_upstream():
    _, per_pattern, _, _ = _pipeline()
    want = {k: v for k, v in GOLDEN["perPattern"].items() if v}
    assert {k: v for k, v in per_pattern.items() if v} == want


def test_sentence_bounds_swallow_trailing_quote():
    text = "He said “that is the whole point.” Then he left."
    start = text.index("the whole")
    _, end = cc.sentence_bounds(text, start, start + len("the whole point"))
    assert text[end - 1] == "”"
