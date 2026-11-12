#!/usr/bin/env python3
"""Behavior tests for hookpath.find_hook, which locates a hook in either layout."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hookpath import ENV_VAR, STAGING_HOOKS, find_hook


class FindHook(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        self.staging, self.home, self.override = (
            root / "staging" / "hooks",
            root / "home",
            root / "override",
        )
        self.live = self.home / ".claude" / "hooks"

    def put(self, d: Path) -> Path:
        d.mkdir(parents=True, exist_ok=True)
        (d / "h.sh").write_text("")
        return d / "h.sh"

    def find(self, env: dict[str, str] | None = None) -> Path | None:
        return find_hook("h.sh", env or {}, staging=self.staging, home=self.home)

    def test_staging_layout_wins_over_live(self) -> None:
        want = self.put(self.staging)
        self.put(self.live)
        self.assertEqual(self.find(), want)

    def test_live_layout_is_the_fallback(self) -> None:
        self.assertIsNone(self.find())
        want = self.put(self.live)
        self.assertEqual(self.find(), want)

    def test_env_override_is_authoritative(self) -> None:
        self.put(self.staging)
        env = {ENV_VAR: str(self.override)}
        self.assertIsNone(self.find(env))
        want = self.put(self.override)
        self.assertEqual(self.find(env), want)

    def test_default_staging_dir_is_the_staging_hooks(self) -> None:
        if not (STAGING_HOOKS.parent / "swap.sh").is_file():
            self.skipTest("not running from the staging tree")
        self.assertTrue((STAGING_HOOKS / "log-dispatch.py").is_file())


if __name__ == "__main__":
    unittest.main()
