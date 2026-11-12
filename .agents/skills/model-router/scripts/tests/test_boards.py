#!/usr/bin/env python3
"""Behaviour tests for boards.py.  stdlib unittest, no network.

Fixtures in fixtures/boards/ are all synthetic: arena.ai, designarena.ai,
eqbench.com, and datasets-server.huggingface.co are denied to the sandbox.
"""

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
FIX = HERE.parents[1] / "assets" / "fixtures" / "boards"

import boards


def fx(name: str) -> bytes:
    return (FIX / name).read_bytes()


def row(key: str, score: float, effort: str | None = None, votes: int | None = 10):
    return {"key": key, "score": score, "ci": None, "effort": effort, "votes": votes}


class ArenaParse(unittest.TestCase):
    def test_chinese_rows_filtered_to_category(self):
        rows = boards.parse_arena_chinese(
            fx("arena_text_chinese_synthetic.json"), min_rows=3
        )
        self.assertEqual(len(rows), 6)
        self.assertNotIn("stray-model", [r["key"] for r in rows])

    def test_row_shape_and_ci_half_width(self):
        rows = boards.parse_arena_chinese(
            fx("arena_text_chinese_synthetic.json"), min_rows=3
        )
        by = {(r["key"], r["effort"]): r for r in rows}
        r = by[("claude-opus-5-5", "high")]
        self.assertEqual(r["score"], 1568.0)
        self.assertEqual(r["ci"], 18.0)
        self.assertEqual(r["votes"], 5200)
        self.assertEqual(set(r), {"key", "score", "ci", "effort", "votes"})

    def test_effort_parsed_and_lowercased(self):
        rows = boards.parse_arena_chinese(
            fx("arena_text_chinese_synthetic.json"), min_rows=3
        )
        efforts = {r["key"]: r["effort"] for r in rows}
        self.assertEqual(efforts["claude-sonnet-5-5"], "xhigh")
        self.assertEqual(efforts["claude-fable-5-1"], "max")
        self.assertIsNone(efforts["gemini-4-argon"])

    def test_min_rows_error(self):
        with self.assertRaises(boards.MinRowsError):
            boards.parse_arena_chinese(fx("arena_text_chinese_synthetic.json"))

    def test_webdev_keeps_only_webdev_category(self):
        rows = boards.parse_arena_webdev(fx("arena_webdev_synthetic.json"), min_rows=3)
        self.assertEqual(len(rows), 4)
        opus = [r for r in rows if r["key"] == "claude-opus-5-5"]
        self.assertEqual([r["score"] for r in opus], [1818.0])
        self.assertEqual(
            [r["effort"] for r in rows if r["key"] == "claude-sonnet-5-5"], ["xhigh"]
        )

    def test_accepts_list_of_pages_and_decoded_json(self):
        page = json.loads(fx("arena_webdev_synthetic.json"))
        rows = boards.parse_arena_webdev([page, page], min_rows=3)
        self.assertEqual(len(rows), 4)  # duplicate keys collapse

    def test_named_wrappers_cover_contract_boards(self):
        for name in (
            "arena_webdev",
            "arena_creative_writing",
            "arena_chinese",
            "arena_japanese",
        ):
            self.assertIn(name, boards.MIN_ROWS)
            self.assertIn(name, boards.FETCH)
            self.assertTrue(callable(getattr(boards, "parse_" + name)))

    def test_every_language_board_has_min_rows_and_fetch(self):
        self.assertEqual(len(boards.ARENA_LANGS), 8)
        for lang in boards.ARENA_LANGS:
            self.assertIn("arena_" + lang, boards.MIN_ROWS)
            self.assertIn("arena_" + lang, boards.FETCH)

    def test_unknown_board_rejected(self):
        with self.assertRaises(KeyError):
            boards.parse_arena(b"{}", "arena_klingon")


# Rows seen on 2026-11-09 (datasets-server /statistics, split latest).
TODAY = {
    "arena_webdev": 153,
    "arena_creative_writing": 418,
    "arena_chinese": 394,
    "arena_korean": 288,
    "arena_french": 300,
    "arena_german": 320,
    "arena_spanish": 303,
    "arena_japanese": 288,
    "arena_russian": 384,
    "arena_polish": 244,
}


class Floors(unittest.TestCase):
    def test_arena_min_rows_are_about_sixty_percent_of_today(self):
        for board, n in TODAY.items():
            self.assertLessEqual(boards.MIN_ROWS[board], n * 0.62, board)
            self.assertGreaterEqual(boards.MIN_ROWS[board], n * 0.58, board)

    def test_eq_bench_min_rows_is_about_three_quarters_of_observed(self):
        observed = 32  # first live refresh, 2026-11-10
        self.assertLessEqual(boards.MIN_ROWS["eq_bench"], observed * 0.78)
        self.assertGreaterEqual(boards.MIN_ROWS["eq_bench"], observed * 0.72)

    def test_category_values(self):
        self.assertEqual(boards.ARENA_CATEGORY["arena_webdev"], ("webdev", "webdev"))
        self.assertEqual(
            boards.ARENA_CATEGORY["arena_creative_writing"],
            ("text", "creative_writing"),
        )


class Means(unittest.TestCase):
    def _boards(self, n: int):
        langs = boards.ARENA_LANGS[:n]
        return {
            "arena_" + lang: [row("m", 1500.0 + i, "high", 100)]
            for i, lang in enumerate(langs)
        }

    def test_lang_mean_needs_five_boards(self):
        self.assertEqual(boards.arena_lang_mean(self._boards(4)), [])
        out = boards.arena_lang_mean(self._boards(5))
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["score"], 1502.0)
        self.assertEqual(out[0]["effort"], "high")
        self.assertEqual(out[0]["votes"], 500)

    def test_lang_mean_all_eight(self):
        out = boards.arena_lang_mean(self._boards(8))
        self.assertEqual(out[0]["score"], 1503.5)

    def test_lang_mean_ignores_non_language_boards(self):
        b = self._boards(4)
        b["arena_webdev"] = [row("m", 1900.0, "high")]
        self.assertEqual(boards.arena_lang_mean(b), [])

    def test_lang_mean_separates_models_and_efforts(self):
        b = self._boards(5)
        b["arena_french"].append(row("m", 1000.0, "max"))
        out = boards.arena_lang_mean(b)
        self.assertEqual([(r["key"], r["effort"]) for r in out], [("m", "high")])

    def test_european_mean_requires_all_five(self):
        eu = {
            "arena_" + lang: [row("m", float(s))]
            for lang, s in zip(boards.ARENA_EUROPEAN, (1500, 1510, 1520, 1530, 1540))
        }
        out = boards.arena_european_mean(eu)
        self.assertEqual(out[0]["score"], 1520.0)
        del eu["arena_polish"]
        self.assertEqual(boards.arena_european_mean(eu), [])

    def test_european_set_is_fr_de_es_pl_ru(self):
        self.assertEqual(
            set(boards.ARENA_EUROPEAN),
            {"french", "german", "spanish", "polish", "russian"},
        )


class DesignArena(unittest.TestCase):
    def test_rows_and_null_elo_dropped(self):
        rows = boards.parse_designarena(fx("designarena_synthetic.json"), min_rows=3)
        self.assertEqual(
            {r["key"]: r["score"] for r in rows},
            {"claude-opus-5-5": 1402.0, "glm-5-3-flash": 1609.0, "kimi-k3": 1356.0},
        )
        self.assertIsNone(rows[0]["ci"])
        self.assertIsNone(rows[0]["effort"])

    def test_min_rows_error(self):
        with self.assertRaises(boards.MinRowsError):
            boards.parse_designarena(fx("designarena_synthetic.json"))

    def test_fetch_is_post(self):
        self.assertEqual(boards.FETCH["design_arena"]["method"], "POST")


class EqBench(unittest.TestCase):
    def test_strips_js_wrapper(self):
        rows = boards.parse_eqbench(fx("eqbench4_synthetic.js"), min_rows=2)
        self.assertEqual(
            {r["key"]: r["score"] for r in rows},
            {"anthropic/claude-opus-5-5": 1339.1, "openai/gpt-6.1-sol": 1271.7},
        )

    def test_min_rows_error(self):
        with self.assertRaises(boards.MinRowsError):
            boards.parse_eqbench(fx("eqbench4_synthetic.js"))

    def test_accepts_str(self):
        rows = boards.parse_eqbench(fx("eqbench4_synthetic.js").decode(), min_rows=2)
        self.assertEqual(len(rows), 2)


class Fetch(unittest.TestCase):
    def test_every_min_rows_has_fetch(self):
        self.assertEqual(set(boards.MIN_ROWS), set(boards.FETCH))

    def test_arena_fetch_uses_datasets_server_not_parquet(self):
        for name, f in boards.FETCH.items():
            if name.startswith("arena_"):
                url = f["url"] or ""
                self.assertTrue(
                    url.startswith("https://datasets-server.huggingface.co/")
                )
                self.assertNotIn("parquet", url)

    def test_arena_reads_rows_not_the_filter_index(self):
        for name, (config, _) in boards.ARENA_CATEGORY.items():
            url = str(boards.FETCH[name]["url"])
            self.assertIn("/rows?", url, name)
            self.assertNotIn("where=", url, name)
            self.assertTrue(url.endswith(f"&config={config}"), name)

    def test_arena_boards_need_only_two_configs(self):
        urls = {str(boards.FETCH[b]["url"]) for b in boards.ARENA_CATEGORY}
        self.assertEqual(len(urls), 2)

    def test_no_matharena(self):
        self.assertFalse(any("math" in k for k in boards.FETCH))


if __name__ == "__main__":
    unittest.main()
