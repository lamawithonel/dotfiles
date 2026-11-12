#!/usr/bin/env python3
"""PostToolUse hook: append one line per real model dispatch to a log.

A dispatch is an `Agent` call that names a model, or a Bash command that
runs `pi --model M --thinking T` or `claude --model M --effort E`
anywhere in it, including a Herdr pane command after `--`.  Each one
becomes a JSON line {ts, session_id, tool, harness, model, effort} in
$MODEL_ROUTER_DISPATCH_LOG, else
$XDG_STATE_HOME/agents/model-router/dispatches.jsonl.  `score.py --mix`
reads the log and assigns bands at report time.

The hook never blocks: it prints nothing on stdout and exits 0 always.
Malformed input and write errors print a warning on stderr.  Workflow
agents are not counted: PostToolUse fires once per Workflow call.
"""

import json
import os
import re
import sys
from collections.abc import Iterator, Mapping
from datetime import UTC, datetime
from typing import Any, Final

# shortcut: a quoted string that holds "pi --model X" also matches; a
# shell parser would fix it, if such text ever shows up in the log.
DISPATCH: Final = re.compile(r"(?<![\w./-])(?:\S*/)?(pi|claude)\s+([^;&|\n]*)")
# A value stops at shell punctuation, so "$(claude --effort high)" logs "high".
OPTION: Final = re.compile(
    r"--(model|thinking|effort)(?:=|\s+)(['\"]?)([^\s'\"()`<>;&|$]+)\2"
)
EFFORT_FLAG: Final = {"pi": "thinking", "claude": "effort"}


def _warn(text: str) -> None:
    print(f"log-dispatch: warning: {text}", file=sys.stderr)


def log_path(env: Mapping[str, str]) -> str:
    if env.get("MODEL_ROUTER_DISPATCH_LOG"):
        return env["MODEL_ROUTER_DISPATCH_LOG"]
    state = env.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "agents", "model-router", "dispatches.jsonl")


def shell_dispatches(command: str) -> Iterator[dict[str, Any]]:
    for match in DISPATCH.finditer(command):
        binary = match.group(1)
        opts = {key: value for key, _, value in OPTION.findall(match.group(2))}
        if "model" in opts:
            yield {
                "harness": binary,
                "model": opts["model"],
                "effort": opts.get(EFFORT_FLAG[binary]),
            }


def dispatches(tool: str, tool_input: Mapping[str, Any]) -> list[dict[str, Any]]:
    if tool == "Agent":
        model = tool_input.get("model")
        if tool_input.get("subagent_type") == "fork" or not isinstance(model, str):
            return []
        if not model.strip():
            return []
        effort = tool_input.get("effort")
        return [{"harness": "claude-code", "model": model, "effort": effort}]
    command = tool_input.get("command")
    if tool == "Bash" and isinstance(command, str):
        return list(shell_dispatches(command))
    return []


def append(path: str, lines: list[str]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        for line in lines:
            os.write(fd, line.encode())  # one short O_APPEND write per line
    finally:
        os.close(fd)


def main() -> int:
    try:
        data = json.loads(sys.stdin.read())
    except ValueError as err:
        _warn(f"input is not JSON: {err}")
        return 0
    if not isinstance(data, dict) or not isinstance(data.get("tool_input"), dict):
        _warn("input is not a hook object with a tool_input object")
        return 0
    found = dispatches(str(data.get("tool_name")), data["tool_input"])
    if not found:
        return 0
    ts = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    base = {"ts": ts, "session_id": data.get("session_id"), "tool": data["tool_name"]}
    lines = [json.dumps({**base, **d}) + "\n" for d in found]
    try:
        append(log_path(os.environ), lines)
    except OSError as err:
        _warn(f"cannot append to the dispatch log: {err}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
