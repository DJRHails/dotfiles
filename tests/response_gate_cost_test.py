"""Pins for response-gate-cost.py's rewrite attribution and argument handling.

The gate's hook feedback is stored as a meta user entry, so the marker has to be tested
before meta entries are discarded; a usage block repeats across the transcript entries
of one API message; and a tool result inside a rewrite does not end it. Each regression
would still print a plausible share, so the numbers are pinned here (review of PR #191).

Run: pytest -q tests/response_gate_cost_test.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

_SCRIPT = Path(__file__).resolve().parent.parent / "modules/claude/scripts/response-gate-cost.py"
_spec = importlib.util.spec_from_file_location("response_gate_cost", _SCRIPT)
assert _spec and _spec.loader
rgc = importlib.util.module_from_spec(_spec)
# @dataclass resolves annotations through sys.modules, so register before exec.
sys.modules[_spec.name] = rgc
_spec.loader.exec_module(rgc)


def _human(text: str) -> str:
    return json.dumps({"type": "user", "message": {"content": text}})


def _feedback() -> str:
    content = [{"type": "text", "text": "Stop hook feedback:\n[bash response-gate.sh]: ..."}]
    return json.dumps({"type": "user", "isMeta": True, "message": {"content": content}})


def _meta(text: str) -> str:
    return json.dumps({"type": "user", "isMeta": True, "message": {"content": text}})


def _tool_result() -> str:
    content = [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]
    return json.dumps({"type": "user", "message": {"content": content}})


def _assistant(mid: str, output: int, read: int = 0) -> str:
    usage = {"input_tokens": 1, "output_tokens": output, "cache_read_input_tokens": read}
    return json.dumps({"type": "assistant", "message": {"id": mid, "usage": usage}})


def test_meta_feedback_entry_marks_following_messages_as_rewrite() -> None:
    t = rgc.tally([_human("hi"), _assistant("m1", 10), _feedback(), _assistant("m2", 30)])
    assert (t.human_prompts, t.feedback_turns) == (1, 1)
    assert t.total["output_tokens"] == 40
    assert t.rewrite["output_tokens"] == 30


def test_usage_counted_once_per_message_id() -> None:
    t = rgc.tally([_human("hi"), _assistant("m1", 5, 100), _assistant("m1", 10, 100)])
    assert t.messages == 1
    assert t.total["output_tokens"] == 10
    assert t.total["cache_read_input_tokens"] == 100


def test_tool_result_and_other_meta_keep_the_rewrite_open() -> None:
    lines = [_feedback(), _assistant("m1", 1), _tool_result(), _meta("skill"), _assistant("m2", 2)]
    t = rgc.tally(lines)
    assert t.rewrite_messages == 2
    assert t.human_prompts == 0


def test_next_human_prompt_ends_the_rewrite() -> None:
    t = rgc.tally([_feedback(), _assistant("m1", 1), _human("next"), _assistant("m2", 2)])
    assert t.rewrite["output_tokens"] == 1


@pytest.mark.parametrize("spec", ["1,2,3", "1,2,x,4", "1,,3,4"])
def test_malformed_prices_exit_with_a_message(spec: str) -> None:
    with pytest.raises(SystemExit, match="four numbers"):
        rgc._parse_prices(spec)


def test_prices_map_to_usage_keys() -> None:
    assert rgc._parse_prices("3,15,0.3,3.75") == {
        "input_tokens": 3.0,
        "output_tokens": 15.0,
        "cache_read_input_tokens": 0.3,
        "cache_creation_input_tokens": 3.75,
    }
