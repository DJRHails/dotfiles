"""Pins for resume-agent-session.py's judgment logic: id parsing and screen evidence.

The evidence check must never verify off the sent command's own echo — locally the echoed
line contains the full session id, so a failed `::resume` sitting at a shell error would
read as a successful resume (review of PR #112). And full_session_id() encodes the exact
transcript filename shapes the claude/pi resolvers produce; if that assumption drifts, the
garbage id flows into the resume command and fails a minute later inside the tab.

Run: pytest -q tests/resume_agent_session_test.py
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

_SCRIPT = (
    Path(__file__).resolve().parent.parent
    / "modules/agents/skills/cmux-rebuild/scripts/resume-agent-session.py"
)
_spec = importlib.util.spec_from_file_location("resume_agent_session", _SCRIPT)
assert _spec and _spec.loader
ras = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ras)

CLAUDE_ID = "375fda41-9a3f-4b2c-8d1e-0aa1b2c3d4e5"
PI_ID = "019ffb15-8130-7778-9440-aabbccddeeff"


def test_full_session_id_claude_stem_is_the_uuid() -> None:
    assert ras.full_session_id("claude", f"/x/projects/y/{CLAUDE_ID}.jsonl") == CLAUDE_ID


def test_full_session_id_pi_strips_timestamp_prefix() -> None:
    stem = f"2026-08-14T10-00-00-000Z_{PI_ID}"
    assert ras.full_session_id("pi", f"/x/sessions/y/{stem}.jsonl") == PI_ID


def test_full_session_id_pi_bare_stem_passes_through() -> None:
    assert ras.full_session_id("pi", f"/x/sessions/y/{PI_ID}.jsonl") == PI_ID


def test_resolved_ids_satisfy_the_uuid_postcondition() -> None:
    for sid in (CLAUDE_ID, PI_ID):
        assert ras.UUID_LINE.fullmatch(sid)


def test_echoed_command_is_typed_not_verified(monkeypatch) -> None:
    cmd = f"claude::resume {CLAUDE_ID}"
    screen = f"~/projects ❯ claude::resume {CLAUDE_ID}\n"
    monkeypatch.setattr(ras._RD, "cmux", lambda *a: screen)
    assert ras.evidence("surface:1", "workspace:1", cmd, CLAUDE_ID, "trifle", None) == "typed"


def test_statusline_id_is_verified(monkeypatch) -> None:
    cmd = f"claude::resume {CLAUDE_ID}"
    screen = (
        f"~/projects ❯ claude::resume {CLAUDE_ID}\n"
        f"░░░░░░░░░░ 0% │ ↑0 ↓0 │ $0 │ {CLAUDE_ID}\n"
    )
    monkeypatch.setattr(ras._RD, "cmux", lambda *a: screen)
    assert ras.evidence("surface:1", "workspace:1", cmd, CLAUDE_ID, "trifle", None) == "verified"


def test_blank_screen_is_no_evidence(monkeypatch) -> None:
    cmd = f"pi::resume {PI_ID}"
    monkeypatch.setattr(ras._RD, "cmux", lambda *a: "")
    assert ras.evidence("surface:1", "workspace:1", cmd, PI_ID, "trifle", None) == ""
