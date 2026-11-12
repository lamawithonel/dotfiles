#!/usr/bin/env python3
"""Token share by model and session role, from Claude Code transcripts.

Reads only metadata: session names, timestamps, models, and usage
counts.  Message content is never stored or printed.
"""

import argparse
import json
import re
import sys
from collections.abc import Iterator, Sequence
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Final

DEFAULT_PROJECTS: Final = Path.home() / ".claude" / "projects"
ROLE_RES: Final = (
    ("orchestrator", re.compile(r"-orchestrator$")),
    ("coordinator", re.compile(r"-(lead|co|coordinator)$")),
    ("pane-worker", re.compile(r"-worker(-\d+)?$")),
)
FAMILIES: Final = ("opus", "sonnet", "haiku", "fable")
FIELDS: Final = ("messages", "output", "input_cache")

Row = tuple[str, int, int]  # model, output tokens, input+cache tokens
Bucket = dict[str, int]


def session_role(path: Path, names: Sequence[str]) -> str:
    """Classify a transcript; the last session name is the current one."""
    if "subagents" in path.parts:  # also Workflow runs, nested deeper
        return "subagent"
    if "pitchfork" in path.parent.name:
        return "scheduled"
    for role, rx in ROLE_RES:
        if names and rx.search(names[-1]):
            return role
    return "independent"


def session_id(path: Path) -> str:
    if "subagents" in path.parts:
        return path.parts[path.parts.index("subagents") - 1]
    return path.stem


def family(model: str) -> str:
    for fam in FAMILIES:
        if fam in model:
            return fam
    return model


def stamp(moment: datetime) -> str:
    return (
        moment.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    )


def _name(rec: dict[str, Any]) -> str | None:
    if rec.get("type") not in ("agent-name", "custom-title"):
        return None
    return rec.get("agentName") or rec.get("customTitle")


def _row(rec: dict[str, Any], since: str, until: str, seen: set[str]) -> Row | None:
    if rec.get("type") != "assistant" or not since <= rec.get("timestamp", "") < until:
        return None
    msg = rec.get("message") or {}
    key = str(msg.get("id") or rec.get("requestId") or "")
    if key and key in seen:  # one API message spans several lines
        return None
    seen.add(key)
    use = msg.get("usage") or {}
    inputs = sum(
        use.get(k, 0)
        for k in (
            "input_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
        )
    )
    return family(msg.get("model", "?")), use.get("output_tokens", 0), inputs


def _records(path: Path) -> Iterator[dict[str, Any]]:
    with path.open(encoding="utf-8", errors="replace") as fh:
        for num, line in enumerate(fh, 1):
            if (
                '"agent-name"' not in line
                and '"custom-title"' not in line
                and '"assistant"' not in line
            ):
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                print(f"warning: {path}:{num}: skipped malformed line", file=sys.stderr)
                continue
            if isinstance(rec, dict):
                yield rec


def scan(path: Path, since: str, until: str) -> tuple[list[str], list[Row]]:
    names: list[str] = []
    rows: list[Row] = []
    seen: set[str] = set()
    for rec in _records(path):
        if (name := _name(rec)) is not None:
            names.append(name)
        elif (row := _row(rec, since, until, seen)) is not None:
            rows.append(row)
    return names, rows


def bump(bucket: Bucket, out: int, inp: int) -> None:
    bucket["messages"] = bucket.get("messages", 0) + 1
    bucket["output"] = bucket.get("output", 0) + out
    bucket["input_cache"] = bucket.get("input_cache", 0) + inp


def collect(
    projects: Path, since: datetime, until: datetime, prefixes: Sequence[str]
) -> tuple[dict[str, dict[str, Bucket]], dict[str, Bucket]]:
    """Return totals keyed role -> model and model."""
    by_role: dict[str, dict[str, Bucket]] = {}
    by_model: dict[str, Bucket] = {}
    floor = since.timestamp()
    for path in sorted(projects.glob("**/*.jsonl")):
        if prefixes and not session_id(path).startswith(tuple(prefixes)):
            continue
        if path.stat().st_mtime < floor:  # untouched since the window opened
            continue
        names, rows = scan(path, stamp(since), stamp(until))
        role = session_role(path, names)
        for model, out, inp in rows:
            bump(by_role.setdefault(role, {}).setdefault(model, {}), out, inp)
            bump(by_model.setdefault(model, {}), out, inp)
    return by_role, by_model


def _table(title: str, rows: dict[str, Bucket], total_out: int) -> list[str]:
    lines = [f"{title:<22}{'msgs':>7}{'output':>12}{'in+cache':>14}{'%out':>7}"]
    for key, b in sorted(rows.items(), key=lambda kv: -kv[1]["output"]):
        pct = 100 * b["output"] / total_out if total_out else 0.0
        lines.append(
            f"{key:<22}{b['messages']:>7}{b['output']:>12}{b['input_cache']:>14}{pct:>6.1f}%"
        )
    return lines


def render(by_role: dict[str, dict[str, Bucket]], by_model: dict[str, Bucket]) -> str:
    role_rows: dict[str, Bucket] = {}
    for role, models in by_role.items():
        agg: Bucket = {}
        for b in models.values():
            for f in FIELDS:
                agg[f] = agg.get(f, 0) + b[f]
        role_rows[role] = agg
    total = sum(b["output"] for b in by_model.values())
    parts = _table("role", role_rows, total) + [""] + _table("model", by_model, total)
    return "\n".join(parts)


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", type=float, default=2, help="window length (default 2)")
    ap.add_argument(
        "--session", action="append", default=[], help="session ID prefix (repeatable)"
    )
    ap.add_argument("--projects", type=Path, default=DEFAULT_PROJECTS)
    ap.add_argument("--now", help="ISO timestamp for the window end (default now)")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    return ap.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    now = datetime.fromisoformat(args.now) if args.now else datetime.now(UTC)
    if now.tzinfo is None:
        now = now.replace(tzinfo=UTC)
    since = now - timedelta(days=args.days)
    by_role, by_model = collect(args.projects, since, now, args.session)
    if args.json:
        doc = {"window": {"since": stamp(since), "until": stamp(now)}}
        doc |= {"by_role": by_role, "by_model": by_model}
        print(json.dumps(doc, indent=1))
    else:
        print(render(by_role, by_model))
    return 0


if __name__ == "__main__":
    sys.exit(main())
