#!/usr/bin/env python3
"""Exercise the real converter in isolated stores, with CLI launchers stubbed."""

import json
import os
import selectors
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
BRIDGE = DATA / "agent-session-bridge"
CLAUDE_ID = "abcd1111-0000-4000-8000-000000000001"
CODEX_ID = "abcd2222-0000-4000-8000-000000000002"


class ResumeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.cwd = self.home / "project with spaces"
        self.cwd.mkdir()
        data = self.home / ".local/share"
        data.mkdir(parents=True)
        (data / "agent-session-bridge").symlink_to(BRIDGE, target_is_directory=True)
        self.env = dict(os.environ, HOME=str(self.home), XDG_DATA_HOME=str(data))
        for key in ("CODEX_HOME", "CLAUDE_CONFIG_DIR"):
            self.env.pop(key, None)
        self.claude = self.home / ".claude-ant/projects/project" / f"{CLAUDE_ID}.jsonl"
        self.codex = self.home / ".codex/sessions/2026/10/16" / f"rollout-{CODEX_ID}.jsonl"
        self.write(self.claude, [
            {"type": "user", "uuid": "u1", "parentUuid": None, "sessionId": CLAUDE_ID,
             "cwd": str(self.cwd), "timestamp": "2026-10-16T10:00:00Z",
             "message": {"role": "user", "content": "Remember hazelnut-417"}},
            {"type": "assistant", "uuid": "a1", "parentUuid": "u1", "sessionId": CLAUDE_ID,
             "cwd": str(self.cwd), "timestamp": "2026-10-16T10:00:01Z",
             "message": {"role": "assistant", "model": "claude-test", "content": [
                 {"type": "text", "text": "I remember hazelnut-417"},
                 {"type": "tool_use", "id": "call-1", "name": "Bash", "input": {"command": "pwd"}}]}},
            {"type": "user", "uuid": "u2", "parentUuid": "a1", "sessionId": CLAUDE_ID,
             "cwd": str(self.cwd), "timestamp": "2026-10-16T10:00:02Z",
             "message": {"role": "user", "content": [
                 {"type": "tool_result", "tool_use_id": "call-1", "content": "tool-result-hazelnut"}]}},
        ])
        self.write(self.codex, [
            {"type": "session_meta", "payload": {"id": CODEX_ID, "cwd": str(self.cwd),
             "originator": "codex_cli_rs", "timestamp": "2026-10-16T10:00:00Z"}},
            {"type": "response_item", "payload": {"type": "message", "role": "user",
             "content": [{"type": "input_text", "text": "Remember pistachio-618"}]}},
            {"type": "response_item", "payload": {"type": "message", "role": "assistant",
             "content": [{"type": "output_text", "text": "I remember pistachio-618"}]}},
            {"type": "response_item", "payload": {"type": "function_call", "call_id": "call-2",
             "name": "exec_command", "arguments": '{"cmd":"pwd"}'}},
            {"type": "response_item", "payload": {"type": "function_call_output", "call_id": "call-2",
             "output": "tool-result-pistachio"}},
        ])

    def write(self, file: Path, records: list[dict]) -> None:
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("".join(json.dumps(record) + "\n" for record in records))

    def launch(self, target: str, session_id: str) -> subprocess.CompletedProcess[str]:
        script = '''
source "$1/modules/claude/aliases.zsh"
source "$1/modules/codex/aliases.zsh"
claude() { print -r -- "CLAUDE $* in $PWD config=${CLAUDE_CONFIG_DIR-unset}"; }
claude::ant() { print -r -- "ANT $* in $PWD"; }
codex() { print -r -- "CODEX $* in $PWD"; }
"$2::resume" "$3" --model test-model
'''
        return subprocess.run(["zsh", "-f", "-c", script, "test", str(REPO), target, session_id],
                              env=self.env, capture_output=True, text=True)

    def test_native_routes_and_prefix_ambiguity(self) -> None:
        result = self.launch("claude", "abcd1111")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"ANT --resume {CLAUDE_ID} --model test-model in {self.cwd}")
        result = self.launch("codex", "abcd2222")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"CODEX resume {CODEX_ID} --model test-model in {self.cwd}")
        result = self.launch("codex", "abcd")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ambiguous", result.stderr)
        self.assertEqual(result.stdout, "")

    @unittest.skipUnless((BRIDGE / "node_modules/tsx").is_dir(), "install the real converter first")
    def test_claude_to_codex_native_file_and_no_rewrite(self) -> None:
        result = self.launch("codex", CLAUDE_ID)
        self.assertEqual(result.returncode, 0, result.stderr)
        converted = next((self.home / ".codex/sessions").rglob(f"rollout-*{CLAUDE_ID}.jsonl"))
        content = converted.read_text()
        records = [json.loads(line) for line in content.splitlines()]
        self.assertEqual(records[0]["type"], "session_meta")
        self.assertNotIn("model_provider", records[0]["payload"])
        self.assertIn("hazelnut-417", content)
        self.assertIn("function_call_output", content)
        self.assertIn("tool-result-hazelnut", content)
        self.assertIn(CLAUDE_ID, (self.home / ".codex/session_index.jsonl").read_text())
        self.assertEqual(converted.stat().st_mode & 0o777, 0o600)
        converted.write_text(content + '{"type":"test_continuation"}\n')
        before = converted.read_bytes()
        result = self.launch("codex", CLAUDE_ID)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(converted.read_bytes(), before)
        self.assertNotIn("converted", result.stderr)

    @unittest.skipUnless(shutil.which("codex") and (BRIDGE / "node_modules/tsx").is_dir(),
                         "requires Codex and the converter")
    def test_installed_codex_can_resume_converted_history(self) -> None:
        result = self.launch("codex", CLAUDE_ID)
        self.assertEqual(result.returncode, 0, result.stderr)
        # thread/resume loads history without starting a model turn or spending tokens.
        with subprocess.Popen(["codex", "app-server"], env=self.env, text=True,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL) as process:
            try:
                def send(message: dict) -> None:
                    process.stdin.write(json.dumps(message) + "\n")
                    process.stdin.flush()

                send({"id": 1, "method": "initialize", "params": {
                    "clientInfo": {"name": "session-resume-test", "version": "1.0"}}})
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    deadline = time.monotonic() + 20
                    while time.monotonic() < deadline:
                        if not selector.select(1):
                            continue
                        line = process.stdout.readline()
                        self.assertTrue(line, "Codex app-server exited before responding")
                        message = json.loads(line)
                        if message.get("id") == 1:
                            send({"method": "initialized"})
                            send({"id": 2, "method": "thread/resume",
                                  "params": {"threadId": CLAUDE_ID}})
                        if message.get("id") == 2:
                            self.assertNotIn("error", message, message)
                            thread = message["result"]["thread"]
                            self.assertEqual(thread["id"], CLAUDE_ID)
                            self.assertIn("hazelnut-417", json.dumps(thread["turns"]))
                            return
                    self.fail("Codex native resume timed out")
            finally:
                process.terminate()
                process.wait(timeout=5)

    @unittest.skipUnless((BRIDGE / "node_modules/tsx").is_dir(), "install the real converter first")
    def test_codex_to_claude_native_file_and_history(self) -> None:
        result = self.launch("claude", CODEX_ID)
        self.assertEqual(result.returncode, 0, result.stderr)
        converted = next((self.home / ".claude/projects").glob(f"*/{CODEX_ID}.jsonl"))
        content = converted.read_text()
        records = [json.loads(line) for line in content.splitlines()]
        self.assertTrue(any(record.get("type") == "assistant" for record in records))
        self.assertIn("pistachio-618", content)
        self.assertIn("tool_use", content)
        self.assertIn("tool-result-pistachio", content)
        self.assertIn(CODEX_ID, (self.home / ".claude/history.jsonl").read_text())
        self.assertIn(f"--resume {CODEX_ID}", result.stdout)
        self.assertIn("config=unset", result.stdout)

    def test_unknown_id_missing_cwd_and_subagents_refuse(self) -> None:
        self.assertNotEqual(self.launch("codex", "ffff").returncode, 0)
        self.write(self.home / ".claude/projects/project/subagents/eeee1111.jsonl", [])
        self.assertNotEqual(self.launch("claude", "eeee").returncode, 0)
        self.cwd.rmdir()
        result = self.launch("codex", CODEX_ID)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot resolve cwd", result.stderr)


if __name__ == "__main__":
    unittest.main()
