#!/usr/bin/env python3
"""Behavior tests for hooks/log-dispatch.py.

Each case runs the hook as a subprocess with the log path set by
MODEL_SELECTION_DISPATCH_LOG, then reads back the lines it appended.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hookpath import find_hook

HOOK = find_hook("log-dispatch.py")


def setUpModule() -> None:
    if HOOK is None:
        raise unittest.SkipTest(
            "log-dispatch.py not found in the staged .claude/hooks or ~/.claude/hooks"
        )


PI_CMD = (
    "pi --model openrouter/z-ai/glm-5.3 --thinking max --no-session "
    '-p "$(cat /tmp/payload.md)" < /dev/null'
)


class LogDispatchTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.log = Path(tmp.name) / "state" / "dispatches.jsonl"

    def run_hook(self, payload: str) -> subprocess.CompletedProcess[str]:
        env = {**os.environ, "MODEL_SELECTION_DISPATCH_LOG": str(self.log)}
        return subprocess.run(
            [sys.executable, str(HOOK)],
            input=payload,
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

    def send(self, tool: str, **tool_input: Any) -> list[dict[str, Any]]:
        payload = {
            "session_id": "s1",
            "hook_event_name": "PostToolUse",
            "tool_name": tool,
            "tool_input": tool_input,
        }
        proc = self.run_hook(json.dumps(payload))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_agent_call_logs_model_and_effort(self) -> None:
        recs = self.send("Agent", model="sonnet", effort="medium", prompt="x")
        self.assertEqual(len(recs), 1)
        rec = recs[0]
        self.assertEqual(rec["session_id"], "s1")
        self.assertEqual(rec["tool"], "Agent")
        self.assertEqual(rec["harness"], "claude-code")
        self.assertEqual((rec["model"], rec["effort"]), ("sonnet", "medium"))
        self.assertRegex(rec["ts"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

    def test_agent_without_effort_logs_null_effort(self) -> None:
        recs = self.send("Agent", model="opus", prompt="x")
        self.assertIsNone(recs[0]["effort"])

    def test_fork_and_modelless_agent_are_not_logged(self) -> None:
        self.assertEqual(self.send("Agent", subagent_type="fork", prompt="x"), [])
        self.assertEqual(self.send("Agent", prompt="x"), [])
        self.assertFalse(self.log.exists())

    def test_pi_template_command_is_logged(self) -> None:
        recs = self.send("Bash", command=PI_CMD)
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0]["harness"], "pi")
        self.assertEqual(recs[0]["model"], "openrouter/z-ai/glm-5.3")
        self.assertEqual(recs[0]["effort"], "max")

    def test_quoted_and_equals_forms(self) -> None:
        recs = self.send("Bash", command="pi --model='z-ai/glm-5.3' --thinking 'low'")
        self.assertEqual((recs[0]["model"], recs[0]["effort"]), ("z-ai/glm-5.3", "low"))

    def test_herdr_pane_after_double_dash(self) -> None:
        cmd = "herdr pane run --tab mr-workers-1 -- choom -n 1000 -- " + PI_CMD
        recs = self.send("Bash", command=cmd)
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0]["harness"], "pi")

    def test_claude_in_a_pane_is_logged(self) -> None:
        cmd = "herdr pane run -- claude --model sonnet --effort high -p hi"
        recs = self.send("Bash", command=cmd)
        self.assertEqual(recs[0]["harness"], "claude")
        self.assertEqual((recs[0]["model"], recs[0]["effort"]), ("sonnet", "high"))

    def test_shell_punctuation_after_a_value_is_not_logged(self) -> None:
        for cmd, want in (
            ("x=$(claude --model opus --effort high)", ("opus", "high")),
            ("(pi --model z-ai/glm-5.3 --thinking low)", ("z-ai/glm-5.3", "low")),
            ("`pi --model q/q --thinking=max`", ("q/q", "max")),
        ):
            rec = self.send("Bash", command=cmd)[-1]
            self.assertEqual((rec["model"], rec["effort"]), want, cmd)

    def test_two_dispatches_in_one_command(self) -> None:
        cmd = f"{PI_CMD}; /usr/local/bin/pi --model qwen/q --thinking low -p y"
        recs = self.send("Bash", command=cmd)
        self.assertEqual(
            [r["model"] for r in recs], ["openrouter/z-ai/glm-5.3", "qwen/q"]
        )

    def test_commands_without_a_dispatch_log_nothing(self) -> None:
        for cmd in ("ls -la", "pi --help", "pip --model x", "api --model x"):
            self.assertEqual(self.send("Bash", command=cmd), [], cmd)
        self.assertFalse(self.log.exists())

    def test_appends_to_existing_log(self) -> None:
        self.send("Agent", model="haiku", effort="low")
        recs = self.send("Agent", model="opus", effort="high")
        self.assertEqual([r["model"] for r in recs], ["haiku", "opus"])

    def test_malformed_input_exits_zero_with_warning(self) -> None:
        for payload in ("", "not json", "[]", '{"tool_name": "Agent"}'):
            proc = self.run_hook(payload)
            self.assertEqual(proc.returncode, 0, payload)
            self.assertEqual(proc.stdout, "")
        self.assertFalse(self.log.exists())

    def test_unwritable_log_warns_and_exits_zero(self) -> None:
        self.log.parent.mkdir()
        self.log.mkdir()  # a directory where the file should be
        proc = self.run_hook(
            json.dumps({"tool_name": "Agent", "tool_input": {"model": "opus"}})
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("log-dispatch: warning", proc.stderr)


if __name__ == "__main__":
    unittest.main()
