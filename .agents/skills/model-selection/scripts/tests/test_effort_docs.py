#!/usr/bin/env python3
"""Contract tests for the effort guidance (start-effort table and role defaults).

The prose lives in references/effort.md and SKILL.md.  These tests pin
the facts a later edit must not drop: the vendor start-effort table,
the re-sweep rule, the executive xhigh candidate note, and the two
effort-scoped worker lines.  The deferred escalation trial must stay out.
"""

import re
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parents[2]
EFFORT = (SKILL / "references" / "effort.md").read_text(encoding="utf-8")
SKILL_MD = (SKILL / "SKILL.md").read_text(encoding="utf-8")


def flat(text: str) -> str:
    """Join wrapped lines so a phrase may span a line break."""
    return re.sub(r"\s+", " ", text)


def table_rows(text: str) -> dict[str, str]:
    """Map the first cell of each start-effort table row to the rest."""
    rows: dict[str, str] = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and line.lstrip().startswith("|"):
            rows[cells[0]] = " ".join(cells[1:])
    return rows


class StartEffortTableTests(unittest.TestCase):
    def test_heading_names_the_table(self) -> None:
        self.assertIn("## 2. Vendor start efforts", EFFORT)

    def test_rows_match_vendor_advice(self) -> None:
        rows = table_rows(EFFORT)
        for model, level in [
            ("Opus 5", "high"),
            ("Fable 5.x", "high"),
            ("Opus 5.5", "medium"),
            ("Haiku 5.5", "medium"),
            ("Opus 4.7 and 4.8", "xhigh"),
        ]:
            with self.subTest(model=model):
                self.assertIn(model, rows)
                self.assertIn(level, rows[model])

    def test_sonnet_row_has_both_levels(self) -> None:
        row = table_rows(EFFORT).get("Sonnet 5.5", "")
        self.assertIn("medium", row)
        self.assertIn("high", row)

    def test_table_cites_the_vendor_page_and_scope(self) -> None:
        text = flat(EFFORT)
        self.assertIn("platform.claude.com/docs/en/build-with-claude/effort", text)
        self.assertIn("vendor advice", text)

    def test_xhigh_scope_note(self) -> None:
        self.assertIn("`xhigh` on Fable 5.2", flat(EFFORT))


class ResweepRuleTests(unittest.TestCase):
    def test_rule_in_effort_md(self) -> None:
        text = flat(EFFORT)
        self.assertIn("Re-sweep rule", text)
        self.assertIn("local evals", text)
        self.assertIn("each model upgrade", text)

    def test_rule_in_skill_md(self) -> None:
        text = flat(SKILL_MD)
        self.assertIn("Re-sweep", text)
        self.assertIn("references/effort.md", text)


class ExecutiveDefaultTests(unittest.TestCase):
    def test_executive_default_is_opus_at_high(self) -> None:
        self.assertIn("Executive: `opus` at `high`", flat(SKILL_MD))
        self.assertIn("Executives run `high`", flat(EFFORT))
        self.assertIn("executives `high`, coordinators `high`", flat(EFFORT))

    def test_no_xhigh_executive_default_remains(self) -> None:
        for name, body in (("effort.md", EFFORT), ("SKILL.md", SKILL_MD)):
            with self.subTest(file=name):
                text = flat(body)
                self.assertNotRegex(text, r"[Ee]xecutives?[^.]*`xhigh`[^.]*default")
                self.assertNotRegex(text, r"Executives? (run|:)[^.]*`xhigh`")
                self.assertNotIn("candidate to test", text)

    def test_skill_files_carry_no_reason_passage(self) -> None:
        for name, body in (("effort.md", EFFORT), ("SKILL.md", SKILL_MD)):
            with self.subTest(file=name):
                self.assertNotIn("Reason:", body)


class WorkerEffortLinesTests(unittest.TestCase):
    def test_stop_once_checks_pass(self) -> None:
        text = flat(EFFORT)
        self.assertIn("At `xhigh` or `max`, a worker stops once its checks pass", text)
        self.assertIn("starts no reviewer subagents", text)

    def test_low_effort_check(self) -> None:
        text = flat(EFFORT)
        self.assertIn("At `low` effort, a worker runs a check", text)
        self.assertIn("exercises each change before it reports done", text)

    def test_skill_md_carries_both_lines(self) -> None:
        text = flat(SKILL_MD)
        self.assertIn("stops once its checks pass", text)
        self.assertIn("exercises each change before it reports done", text)


class DeferredItemsStayOutTests(unittest.TestCase):
    def test_no_escalation_trial(self) -> None:
        for body in (EFFORT, SKILL_MD):
            text = flat(body).lower()
            self.assertNotIn("escalation trial", text)
            self.assertNotIn("raise effort one level only after", text)


if __name__ == "__main__":
    unittest.main()
