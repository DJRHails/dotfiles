#!/usr/bin/env python3
"""Prepare native history, retaining the source and any existing target copy."""

import fcntl
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from resolve import resolve


def prepare(target: str, prefix: str) -> dict[str, str]:
    info = resolve(target, prefix)
    if info["source"] == target:
        return info
    data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    bridge = data / "agent-session-bridge"
    if not (bridge / "node_modules/tsx").is_dir():
        raise ValueError(f"install the converter first: bash {Path(__file__).parent}/install.sh")
    os.umask(0o077)
    locks = data / "agent-session-resume-locks"
    locks.mkdir(parents=True, exist_ok=True)
    with (locks / f"{target}-{info['id']}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Another launcher may have converted this ID while we waited.
        info = resolve(target, prefix)
        if info["source"] == target:
            return info
        args = ["node", "--import", str(bridge / "node_modules/tsx/dist/loader.mjs"),
                str(bridge / "src/cli.ts"), f"{info['source']}2{target}", info["file"], "--json",
                "--claude-home", info["claude_home"], "--codex-home", info["codex_home"]]
        if target == "codex":
            now = datetime.now(timezone.utc)
            output = (Path(info["codex_home"]) / "sessions" / now.strftime("%Y/%m/%d")
                      / f"rollout-{now.strftime('%Y-%m-%dT%H-%M-%S')}-{info['id']}.jsonl")
            args += ["--output", str(output)]
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        report = json.loads(result.stdout)
        if not report.get("success"):
            raise ValueError("native session conversion failed")
        if target == "codex":
            # A Claude provider isn't a configured Codex provider. Leave it unset
            # so native resume uses the user's current provider/model settings.
            output = Path(report["outputFile"])
            records = [json.loads(line) for line in output.read_text().splitlines()]
            for record in records:
                if record.get("type") == "session_meta":
                    record["payload"].pop("model_provider", None)
            output.write_text("".join(json.dumps(record) + "\n" for record in records))
        print(f"{target}::resume: converted {info['source']} session {info['id']} to native {target} history", file=sys.stderr)
        if report.get("lossyFields"):
            print("Conversion limitations: " + ", ".join(report["lossyFields"]), file=sys.stderr)
        return resolve(target, info["id"])


if __name__ == "__main__":
    try:
        print(json.dumps(prepare(sys.argv[1], sys.argv[2])))
    except subprocess.CalledProcessError as error:
        print(error.stderr or error.stdout or str(error), file=sys.stderr)
        sys.exit(1)
    except (ValueError, OSError) as error:
        print(f"{sys.argv[1]}::resume: {error}", file=sys.stderr)
        sys.exit(1)
