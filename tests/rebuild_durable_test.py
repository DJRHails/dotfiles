"""Regression pin for rebuild-durable.py's husk classifier (HUSK_NOISE).

The MEANINGFUL check guards --retry from hijacking live tabs: a session whose whole pane tree
matches HUSK_NOISE is judged a bare husk — never resumed, and its surface is treated as safe to
send an attach into. Unanchored helper patterns used to classify real work as noise
(`vim caffeinate.txt` matched `caffeinate`, `ripgrep foo` matched `grep `), so a live working
tab could be hijacked. Pin both directions.

Run: pytest -q tests/rebuild_durable_test.py   (or: python3 tests/rebuild_durable_test.py)
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

_SCRIPT = (
    Path(__file__).resolve().parent.parent
    / "modules/agents/skills/cmux-rebuild/scripts/rebuild-durable.py"
)
_spec = importlib.util.spec_from_file_location("rebuild_durable", _SCRIPT)
assert _spec and _spec.loader
rebuild_durable = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rebuild_durable)

NOISE = [
    "zellij attach cmux-trifle-10-generous-pikes",
    "/usr/local/bin/zellij --server /tmp/zellij-501/0.43.1/cmux-trifle-10-generous-pikes",
    "-zsh",
    "/bin/zsh -il",
    "sh -c 'snapshot-zsh 1 2 eval'",
    "login -pf daniel",
    "ps -axww -o pid=,ppid=,command=",
    "ps -ao ppid,args",
    "awk '{print $1}'",
    "/usr/bin/sed -E s/x/y/",
    "grep -c foo",
    "head -5",
    "caffeinate -dims",
]

MEANINGFUL = [
    "claude --resume abc123",
    "vim notes.txt",
    "npm run build",
    "cargo build --release",
    "mosh-client 100.1.2.3 60001",
    # regression: real work that the old unanchored substrings classified as noise
    "vim caffeinate.txt",
    "ripgrep foo",
    "python3 process_data.py --grep foo",
    "node esbuild --head -x",
]


def test_noise_commands_match() -> None:
    for cmd in NOISE:
        assert rebuild_durable.HUSK_NOISE.search(cmd), f"should be noise: {cmd!r}"


def test_real_work_does_not_match() -> None:
    for cmd in MEANINGFUL:
        assert not rebuild_durable.HUSK_NOISE.search(cmd), f"should be meaningful: {cmd!r}"


if __name__ == "__main__":
    test_noise_commands_match()
    test_real_work_does_not_match()
    print("ok")
