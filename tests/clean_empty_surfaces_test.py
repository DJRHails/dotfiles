"""Regression pin for clean-empty-surfaces.py's cmux_tree() fail-loud behavior.

A timed-out `cmux tree` used to parse as zero surfaces and print "no empty surfaces" —
indistinguishable from a genuinely clean tree, silently cancelling the cleanup (PR #112).
Pin both directions: persistent failure (nonzero exit, empty output, or a hang) raises
TreeSnapshotError instead of degrading to an empty snapshot, and a mid-retry success
returns the snapshot.

Run: pytest -q tests/clean_empty_surfaces_test.py
"""
from __future__ import annotations

import importlib.util
import subprocess
from pathlib import Path

import pytest

_SCRIPT = (
    Path(__file__).resolve().parent.parent
    / "modules/agents/skills/cmux-rebuild/scripts/clean-empty-surfaces.py"
)
_spec = importlib.util.spec_from_file_location("clean_empty_surfaces", _SCRIPT)
assert _spec and _spec.loader
ces = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ces)

GOOD_TREE = (
    '├── workspace workspace:13 CD036294-1111-2222-3333-44445555C456 "decal"\n'
    '│   ├── surface surface:26 AD03747D-1111-2222-3333-444455554665 [terminal] "decal-62"\n'
)


def _fake_run(outcomes: list, calls: list):
    """Each outcome is (returncode, stdout) or a subprocess.TimeoutExpired to raise."""

    def run(cmd, **kw):
        calls.append(cmd)
        outcome = outcomes[min(len(calls) - 1, len(outcomes) - 1)]
        if isinstance(outcome, subprocess.TimeoutExpired):
            raise outcome
        rc, out = outcome
        return subprocess.CompletedProcess(cmd, rc, stdout=out, stderr="tree timed out")

    return run


def test_persistent_failure_raises_after_all_attempts(monkeypatch) -> None:
    calls: list = []
    monkeypatch.setattr(ces, "TREE_RETRY_WAIT", 0)
    monkeypatch.setattr(ces.subprocess, "run", _fake_run([(1, "")], calls))
    with pytest.raises(ces.TreeSnapshotError):
        ces.cmux_tree()
    assert len(calls) == ces.TREE_ATTEMPTS


def test_zero_surface_snapshot_is_unreadable_not_clean(monkeypatch) -> None:
    # The old behavior: rc 0 with no surface rows parsed as "no empty surfaces" — success-shaped.
    calls: list = []
    monkeypatch.setattr(ces, "TREE_RETRY_WAIT", 0)
    monkeypatch.setattr(ces.subprocess, "run", _fake_run([(0, "")], calls))
    with pytest.raises(ces.TreeSnapshotError):
        ces.cmux_tree()


def test_mid_retry_success_returns_snapshot(monkeypatch) -> None:
    calls: list = []
    monkeypatch.setattr(ces, "TREE_RETRY_WAIT", 0)
    monkeypatch.setattr(ces.subprocess, "run", _fake_run([(1, ""), (0, GOOD_TREE)], calls))
    assert ces.cmux_tree() == GOOD_TREE
    assert len(calls) == 2


def test_hung_call_is_a_retryable_attempt(monkeypatch) -> None:
    calls: list = []
    hang = subprocess.TimeoutExpired(["cmux", "tree"], ces.TREE_TIMEOUT)
    monkeypatch.setattr(ces, "TREE_RETRY_WAIT", 0)
    monkeypatch.setattr(ces.subprocess, "run", _fake_run([hang, (0, GOOD_TREE)], calls))
    assert ces.cmux_tree() == GOOD_TREE
    assert len(calls) == 2
