#!/usr/bin/env python3
"""Tests for token-share.py on synthetic transcripts.

Fixtures under assets/fixtures/transcripts/ mimic ~/.claude/projects.
The fixed --now keeps the window deterministic.
"""

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any, Final

HERE: Final = Path(__file__).resolve().parent
SCRIPT: Final = HERE.parent / "token-share.py"
FIXTURES: Final = HERE.parents[1] / "assets" / "fixtures" / "transcripts"
NOW: Final = "2026-11-12T00:00:00Z"


def run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            "-B",
            str(SCRIPT),
            "--projects",
            str(FIXTURES),
            "--now",
            NOW,
            *args,
        ],
        capture_output=True,
        text=True,
        check=False,
    )


spec = importlib.util.spec_from_file_location("token_share", SCRIPT)
assert spec and spec.loader
token_share = importlib.util.module_from_spec(spec)
spec.loader.exec_module(token_share)


def report(*args: str) -> dict[str, Any]:
    proc = run("--json", *args)
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


class TokenShareTests(unittest.TestCase):
    def test_duplicate_message_ids_counted_once(self) -> None:
        opus = report()["by_role"]["executive"]["opus"]
        self.assertEqual(opus["messages"], 1)
        self.assertEqual(opus["output"], 100)
        self.assertEqual(opus["input_cache"], 60)

    def test_records_outside_window_ignored(self) -> None:
        self.assertEqual(report()["by_role"]["executive"]["opus"]["output"], 100)

    def test_days_widens_window(self) -> None:
        self.assertEqual(
            report("--days", "30")["by_role"]["executive"]["opus"]["output"], 1099
        )

    def test_roles(self) -> None:
        roles = report()["by_role"]
        self.assertEqual(roles["coordinator"]["opus"]["output"], 50)
        self.assertEqual(roles["subagent"]["haiku"]["output"], 40)
        self.assertEqual(roles["scheduled"]["haiku"]["output"], 7)
        self.assertEqual(roles["standalone"]["sonnet"]["output"], 210)

    def test_session_names_map_to_classes(self) -> None:
        cases = {
            "agents-config-executive": "executive",
            "agents-config-orchestrator": "executive",
            "model-selection-co": "coordinator",
            "agents-config-consultant-2": "consultant",
            "agents-config-security-consultant": "consultant",
            "jiv-workers-1": "standalone",
            "docs-worker-3": "pane-worker",
            "scratch": "standalone",
        }
        for name, role in cases.items():
            with self.subTest(name=name):
                path = Path("/p/proj/s.jsonl")
                self.assertEqual(token_share.session_role(path, [name]), role)

    def test_workflow_agents_count_as_subagents_of_their_session(self) -> None:
        # Workflow runs nest under subagents/workflows/<run id>/.
        data = report("--session", "aaaa1111")
        self.assertEqual(data["by_role"]["subagent"]["sonnet"]["output"], 30)

    def test_by_model_totals(self) -> None:
        self.assertEqual(report()["by_model"]["sonnet"]["output"], 240)

    def test_session_prefix_filter(self) -> None:
        data = report("--session", "aaaa1111")
        self.assertEqual(sorted(data["by_role"]), ["executive", "subagent"])

    def test_content_never_printed(self) -> None:
        for flag in ("--json", "--days"):
            args = [flag] if flag == "--json" else [flag, "2"]
            proc = run(*args)
            self.assertNotIn("SECRET-CONTENT", proc.stdout)
            self.assertNotIn("SECRET-CONTENT", proc.stderr)

    def test_table_has_percent_of_output(self) -> None:
        proc = run()
        self.assertEqual(proc.returncode, 0)
        self.assertIn("executive", proc.stdout)
        self.assertIn("%", proc.stdout)

    def test_malformed_line_warns_and_continues(self) -> None:
        proc = run("--json")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("dddd4444", proc.stderr)
        self.assertIn("warning", proc.stderr)
        self.assertEqual(json.loads(proc.stdout)["by_model"]["sonnet"]["messages"], 3)


if __name__ == "__main__":
    unittest.main()
