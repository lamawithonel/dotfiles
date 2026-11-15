#!/usr/bin/env python3
"""Behavior tests for the rules the skill text states."""

import re
import unittest
from pathlib import Path

SKILL = Path(__file__).resolve().parents[2]
DOCS = [SKILL / "SKILL.md", *sorted((SKILL / "references").glob("*.md"))]
GUARDS = ("STALL WATCHDOG", "SCOPE LIMIT", "RECEIPT CONTRACT")


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class WorkerGuards(unittest.TestCase):
    def test_no_doc_names_a_turn_limit(self) -> None:
        for doc in DOCS:
            with self.subTest(doc=doc.name):
                self.assertNotRegex(text(doc), r"(?i)turn (budget|ceiling|limit)")

    def test_skill_and_brief_template_keep_the_guards(self) -> None:
        for doc in (SKILL / "SKILL.md", SKILL / "references" / "brief.md"):
            for guard in GUARDS:
                with self.subTest(doc=doc.name, guard=guard):
                    self.assertIn(guard, text(doc))

    def test_skill_guards_are_numbered_from_one(self) -> None:
        pattern = rf"^(\d+)\. (?:{'|'.join(GUARDS)}):"
        nums = re.findall(pattern, text(SKILL / "SKILL.md"), re.MULTILINE)
        self.assertEqual(nums, ["1", "2", "3"])

    def test_no_doc_counts_the_guards_in_prose(self) -> None:
        count = r"(?i)\b(two|three|four|five|\d+) (worker )?(guards|invariants)\b"
        for doc in DOCS:
            with self.subTest(doc=doc.name):
                self.assertNotRegex(text(doc), count)


class InlineBudget(unittest.TestCase):
    def test_skill_points_to_agents_md_for_the_inline_budget(self) -> None:
        body = text(SKILL / "SKILL.md")
        self.assertIn("INLINE BUDGET in `~/.agents/AGENTS.md`", body)
        self.assertNotIn("INLINE BUDGET:", body)
        self.assertIn("Weigh your own band.", body)


class HaikuRule(unittest.TestCase):
    def test_caller_rubric_routes_small_read_only_packages_to_haiku(self) -> None:
        rubric = (
            text(SKILL / "SKILL.md").split("## 2. Caller rubric")[1].split("## 3.")[0]
        )
        self.assertRegex(rubric, r"(?s)read-only.*three files or fewer.*`haiku`")


class RawQuotes(unittest.TestCase):
    def test_brief_requires_quotes_from_raw_text(self) -> None:
        brief = text(SKILL / "references" / "brief.md")
        self.assertIn("raw text", brief)
        self.assertIn("WebFetch", brief)
        self.assertIn("second-hand", brief)


if __name__ == "__main__":
    unittest.main()
