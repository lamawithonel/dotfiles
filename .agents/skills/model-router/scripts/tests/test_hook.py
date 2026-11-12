#!/usr/bin/env python3
"""Behavior tests for hooks/require-agent-model.sh.

Each case runs the hook as a subprocess.  The JSON backend is forced by a
PATH that holds only the tools that backend needs, so the jq branch and
the python3 branch are both exercised.  The fallback with neither tool
is tested on its own.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Sequence
from pathlib import Path
from typing import ClassVar

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hookpath import find_hook

HOOK = find_hook("require-agent-model.sh")


def setUpModule() -> None:
    if HOOK is None:
        raise unittest.SkipTest(
            "require-agent-model.sh not found in staging/hooks or ~/.claude/hooks"
        )


REASON = (
    "Agent call has no model.  Run "
    "~/.agents/skills/model-router/scripts/score.py --pick --band <band> "
    "and pass its model_param as model and its effort as effort."
)
EFFORT_REASON = (
    "Agent call has no effort.  Every dispatch names its model and effort "
    "(~/.agents/AGENTS.md, Delegation).  Pass the effort that "
    "~/.agents/skills/model-router/scripts/score.py --pick returned."
)


def _payload(tool: str = "Agent", **tool_input: str) -> str:
    return json.dumps({"tool_name": tool, "tool_input": tool_input})


def _bin_dir(root: Path, tools: Sequence[str]) -> Path:
    bin_dir = root / "bin"
    bin_dir.mkdir()
    for tool in tools:
        found = shutil.which(tool)
        if found is None:
            raise unittest.SkipTest(f"{tool} is not installed")
        (bin_dir / tool).symlink_to(found)
    return bin_dir


class _HookCases(unittest.TestCase):
    """Shared behavior cases; subclasses set `tools` to pick a backend.

    The base class has no backend, so its own run is skipped.
    """

    tools: ClassVar[tuple[str, ...] | None] = None

    def setUp(self) -> None:
        if self.tools is None:
            raise unittest.SkipTest("abstract base; run by the backend subclasses")
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = str(_bin_dir(Path(tmp.name), self.tools))

    def run_hook(self, payload: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/sh", str(HOOK)],
            input=payload,
            capture_output=True,
            text=True,
            env={"PATH": self.path},
            check=False,
        )

    def assert_allowed(self, proc: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")

    def assert_denied(
        self, proc: subprocess.CompletedProcess[str], reason: str = REASON
    ) -> None:
        self.assertEqual(proc.returncode, 0, proc.stderr)
        spec = json.loads(proc.stdout)["hookSpecificOutput"]
        self.assertEqual(spec["hookEventName"], "PreToolUse")
        self.assertEqual(spec["permissionDecision"], "deny")
        self.assertEqual(spec["permissionDecisionReason"], reason)

    def assert_malformed(self, proc: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")
        self.assertIn("malformed", proc.stderr)

    def test_model_present_allows(self) -> None:
        proc = self.run_hook(
            _payload(
                model="sonnet",
                effort="medium",
                subagent_type="general-purpose",
                prompt="x",
            )
        )
        self.assert_allowed(proc)

    def test_effort_missing_denies_naming_the_rule(self) -> None:
        proc = self.run_hook(_payload(model="sonnet", prompt="x"))
        self.assert_denied(proc, EFFORT_REASON)

    def test_blank_effort_denies(self) -> None:
        proc = self.run_hook(_payload(model="sonnet", effort=" \t", prompt="x"))
        self.assert_denied(proc, EFFORT_REASON)

    def test_non_string_effort_denies(self) -> None:
        payload = json.dumps(
            {"tool_name": "Agent", "tool_input": {"model": "opus", "effort": 3}}
        )
        self.assert_denied(self.run_hook(payload), EFFORT_REASON)

    def test_model_missing_denies(self) -> None:
        self.assert_denied(self.run_hook(_payload(prompt="x")))

    def test_model_empty_denies(self) -> None:
        self.assert_denied(self.run_hook(_payload(model="", prompt="x")))

    def test_fork_without_model_allows(self) -> None:
        self.assert_allowed(self.run_hook(_payload(subagent_type="fork", prompt="x")))

    def test_non_agent_tool_allows(self) -> None:
        self.assert_allowed(self.run_hook(_payload(tool="Bash", command="ls")))

    def test_malformed_json_allows_with_warning(self) -> None:
        self.assert_malformed(self.run_hook("{not json"))

    def test_whitespace_only_model_denies(self) -> None:
        self.assert_denied(self.run_hook(_payload(model=" \t\n\r ", prompt="x")))

    def test_non_string_model_denies(self) -> None:
        payload = json.dumps({"tool_name": "Agent", "tool_input": {"model": 5}})
        self.assert_denied(self.run_hook(payload))

    def test_padded_model_allows(self) -> None:
        proc = self.run_hook(_payload(model=" sonnet ", effort="high", prompt="x"))
        self.assert_allowed(proc)

    def test_concatenated_objects_allow_with_warning(self) -> None:
        payload = _payload(model="sonnet") + _payload(model="sonnet")
        self.assert_malformed(self.run_hook(payload))

    def test_empty_input_allows_with_warning(self) -> None:
        self.assert_malformed(self.run_hook(""))

    def test_top_level_array_allows_with_warning(self) -> None:
        self.assert_malformed(self.run_hook("[]"))

    def test_string_tool_input_allows_with_warning(self) -> None:
        payload = json.dumps({"tool_name": "Agent", "tool_input": "str"})
        self.assert_malformed(self.run_hook(payload))

    def test_missing_tool_input_allows_with_warning(self) -> None:
        self.assert_malformed(self.run_hook(json.dumps({"tool_name": "Agent"})))

    def test_string_tool_input_on_other_tool_allows_with_warning(self) -> None:
        payload = json.dumps({"tool_name": "Bash", "tool_input": "ls"})
        self.assert_malformed(self.run_hook(payload))


class JqBackend(_HookCases):
    tools = ("jq", "cat")


class PythonBackend(_HookCases):
    tools = ("python3", "cat")


class NoBackend(unittest.TestCase):
    def test_no_jq_or_python_allows_with_warning(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = str(_bin_dir(Path(tmp.name), []))
        proc = subprocess.run(
            ["/bin/sh", str(HOOK)],
            input=_payload(prompt="x"),
            capture_output=True,
            text=True,
            env={"PATH": path},
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, "")
        self.assertIn("warn", proc.stderr.lower())


if __name__ == "__main__":
    unittest.main()
