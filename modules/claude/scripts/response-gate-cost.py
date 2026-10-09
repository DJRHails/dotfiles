#!/usr/bin/env python3
"""Share of a Claude Code session's tokens spent on response-gate rewrites.

Usage: response-gate-cost.py <transcript.jsonl>... [--prices IN,OUT,READ,WRITE]

A rewrite turn is every assistant message after a user entry carrying
"Stop hook feedback:" and before the next human prompt. Usage is counted once
per API message id, since one message is stored as several transcript entries.
With --prices (dollars per million tokens for input, output, cache read and
cache write) the table gains a dollar column; without it, token shares alone
answer "is the gate within budget", because its cost is pure token cost.

Transcripts live under ~/.claude*/projects/<project-slug>/<session-id>.jsonl.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

USAGE_KEYS = (
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
)
FEEDBACK_MARK = "Stop hook feedback:"


@dataclass
class Tally:
    """Token totals, overall and for rewrite turns only."""

    total: dict[str, int] = field(default_factory=lambda: dict.fromkeys(USAGE_KEYS, 0))
    rewrite: dict[str, int] = field(default_factory=lambda: dict.fromkeys(USAGE_KEYS, 0))
    messages: int = 0
    rewrite_messages: int = 0
    feedback_turns: int = 0
    human_prompts: int = 0


def _text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(
            str(block.get("text", ""))
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        )
    return ""


def _is_tool_result(content: object) -> bool:
    return isinstance(content, list) and any(
        isinstance(block, dict) and block.get("type") == "tool_result" for block in content
    )


def tally(lines: Iterable[str]) -> Tally:
    """Walk one transcript and split its usage into rewrite turns and the rest."""
    out = Tally()
    seen: dict[str, dict[str, int]] = {}
    in_rewrite: dict[str, bool] = {}
    rewriting = False
    for raw in lines:
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError:
            continue
        message = entry.get("message") or {}
        if entry.get("type") == "user":
            content = message.get("content")
            if _is_tool_result(content):
                continue
            # Hook feedback is stored as a meta user entry, so test for the
            # marker before discarding meta entries.
            if FEEDBACK_MARK in _text(content):
                rewriting = True
                out.feedback_turns += 1
            elif not entry.get("isMeta"):
                rewriting = False
                out.human_prompts += 1
        elif entry.get("type") == "assistant":
            usage, mid = message.get("usage"), message.get("id")
            if not usage or not mid:
                continue
            prev = seen.get(mid, {})
            seen[mid] = {k: max(prev.get(k, 0), usage.get(k) or 0) for k in USAGE_KEYS}
            in_rewrite[mid] = in_rewrite.get(mid, False) or rewriting
    for mid, usage in seen.items():
        out.messages += 1
        for key in USAGE_KEYS:
            out.total[key] += usage[key]
        if in_rewrite[mid]:
            out.rewrite_messages += 1
            for key in USAGE_KEYS:
                out.rewrite[key] += usage[key]
    return out


def _dollars(usage: dict[str, int], prices: dict[str, float]) -> float:
    return sum(usage[key] * prices[key] / 1_000_000 for key in USAGE_KEYS)


def _parse_prices(spec: str | None) -> dict[str, float] | None:
    if spec is None:
        return None
    parts = [float(p) for p in spec.split(",")]
    if len(parts) != 4:
        raise SystemExit("--prices wants four numbers: IN,OUT,READ,WRITE dollars per million")
    return dict(zip(USAGE_KEYS, parts, strict=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("transcripts", nargs="+", type=Path)
    parser.add_argument("--prices", metavar="IN,OUT,READ,WRITE", help="$ per million tokens")
    args = parser.parse_args(argv)
    prices = _parse_prices(args.prices)

    combined = Tally()
    for path in args.transcripts:
        try:
            one = tally(path.read_text(encoding="utf-8").splitlines())
        except OSError as err:
            print(f"response-gate-cost: cannot read {path}: {err}", file=sys.stderr)
            return 2
        for key in USAGE_KEYS:
            combined.total[key] += one.total[key]
            combined.rewrite[key] += one.rewrite[key]
        combined.messages += one.messages
        combined.rewrite_messages += one.rewrite_messages
        combined.feedback_turns += one.feedback_turns
        combined.human_prompts += one.human_prompts

    t = combined
    print(
        f"transcripts {len(args.transcripts)}  human prompts {t.human_prompts}  "
        f"gate rewrites {t.feedback_turns}  api messages {t.messages} "
        f"(in rewrites {t.rewrite_messages})"
    )
    print(f"{'tokens':<28}{'total':>14}{'rewrites':>12}{'share':>8}")
    for key in USAGE_KEYS:
        share = t.rewrite[key] / t.total[key] * 100 if t.total[key] else 0.0
        print(f"{key:<28}{t.total[key]:>14,}{t.rewrite[key]:>12,}{share:>7.2f}%")
    if prices:
        total_usd, rewrite_usd = _dollars(t.total, prices), _dollars(t.rewrite, prices)
        share = rewrite_usd / total_usd * 100 if total_usd else 0.0
        print(f"{'dollars':<28}{total_usd:>14.2f}{rewrite_usd:>12.2f}{share:>7.2f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
