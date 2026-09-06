"""Behaviour tests for score.py.  stdlib unittest, no network."""

import importlib.util
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("score", SCRIPTS / "score.py")
assert spec is not None and spec.loader is not None
score = importlib.util.module_from_spec(spec)
spec.loader.exec_module(score)

TODAY = "2026-09-06"


def model(**b):
    fields = {k: None for k in score.BENCH_FIELDS}
    fields.update({k: v for k, v in b.items() if k in score.BENCH_FIELDS})
    return {
        "provider": "x",
        "match": {},
        "benchmarks": fields,
        "pricing": {
            "prompt_cost_per_m": b.get("p", 1.0),
            "completion_cost_per_m": b.get("c", 1.0),
            "source": "openrouter",
        },
        "last_seen": {
            k: b.get("seen", TODAY)
            for k in (
                "aa_api",
                "aa_omniscience",
                "deep_swe",
                "eq_bench",
                "design_arena",
                "openrouter",
            )
        },
        "benchmark_versions": {},
    }


def entry(enabled=True, harness="pi"):
    return {"enabled": enabled, "native_harness": [harness], "execution": {}}


def registry(models, roster=None, overrides=None):
    return {
        "schema_version": 3,
        "updated_at": TODAY + "T00:00:00Z",
        "sources": {},
        "overrides": overrides or {},
        "models": models,
        "hosts": {
            "h": {
                "probed_at": TODAY + "T00:00:00Z",
                "probed_with": {},
                "channels": {"pi": True, "claude-code": True},
                "roster": roster
                if roster is not None
                else {k: entry() for k in models},
            }
        },
    }


class Normalize(unittest.TestCase):
    def test_minmax_across_scored_models(self):
        reg = registry(
            {
                "a/1": model(aa_coding=10),
                "a/2": model(aa_coding=20),
                "a/3": model(aa_coding=30),
            }
        )
        cands = score.candidates(reg, "h", TODAY)
        n = score.normalized(cands, "aa_coding")
        self.assertEqual(n["a/1"], 0.0)
        self.assertEqual(n["a/2"], 0.5)
        self.assertEqual(n["a/3"], 1.0)

    def test_single_scored_model_norms_to_one(self):
        reg = registry({"a/1": model(aa_coding=10), "a/2": model()})
        n = score.normalized(score.candidates(reg, "h", TODAY), "aa_coding")
        self.assertEqual(n, {"a/1": 1.0})

    def test_aged_out_value_is_null(self):
        reg = registry(
            {"a/1": model(aa_coding=10, seen="2026-01-01"), "a/2": model(aa_coding=20)}
        )
        n = score.normalized(score.candidates(reg, "h", TODAY), "aa_coding")
        self.assertNotIn("a/1", n)

    def test_non_primary_version_is_null(self):
        reg = registry(
            {"a/1": model(terminal_bench=50), "a/2": model(terminal_bench=60)}
        )
        reg["models"]["a/1"]["benchmark_versions"] = {"terminal_bench": "2.0"}
        reg["sources"]["aa_api"] = {
            "name": "x",
            "status": "ok",
            "as_of": TODAY,
            "primary_version": "2.1",
        }
        n = score.normalized(score.candidates(reg, "h", TODAY), "terminal_bench")
        self.assertNotIn("a/1", n)


class Quality(unittest.TestCase):
    def test_weights_renormalize_over_non_null(self):
        reg = registry(
            {
                "a/1": model(aa_coding=10, deep_swe=0),
                "a/2": model(aa_coding=20, deep_swe=100),
                "a/3": model(aa_coding=15),
            }
        )
        q = score.quality(
            score.candidates(reg, "h", TODAY), {"aa_coding": 0.5, "deep_swe": 0.5}
        )
        self.assertAlmostEqual(q["a/2"]["Q"], 1.0)
        self.assertAlmostEqual(
            q["a/3"]["Q"], 0.5
        )  # only aa_coding, norm 0.5, weight renormalized to 1
        self.assertEqual(q["a/3"]["n"], 1)

    def test_all_null_model_is_ineligible(self):
        reg = registry(
            {"a/1": model(aa_coding=10), "a/2": model(aa_coding=20), "a/3": model()}
        )
        q = score.quality(score.candidates(reg, "h", TODAY), {"aa_coding": 1})
        self.assertNotIn("a/3", q)

    def test_blended_cost(self):
        self.assertAlmostEqual(
            score.blended_cost(
                {"prompt_cost_per_m": 1.0, "completion_cost_per_m": 3.0}
            ),
            1.5,
        )
        self.assertIsNone(
            score.blended_cost(
                {"prompt_cost_per_m": None, "completion_cost_per_m": 3.0}
            )
        )


class Candidates(unittest.TestCase):
    def test_tier4_only_excluded_and_disabled_excluded_and_track_only_excluded(self):
        models = {
            "a/1": model(aa_coding=1),
            "a/2": model(aa_coding=2),
            "a/3": model(aa_coding=3),
            "a/4": model(aa_coding=4),
        }
        models["a/4"]["track_only"] = True
        reg = registry(
            models,
            roster={"a/1": entry(), "a/2": entry(enabled=False), "a/3": entry()},
            overrides={"a/3": {"constraints": {"tier_4_only": True}}},
        )
        ids = set(score.candidates(reg, "h", TODAY))
        self.assertEqual(ids, {"a/1"})

    def test_track_only_included_when_asked(self):
        models = {"a/1": model(aa_coding=1), "a/4": model(aa_coding=4)}
        models["a/4"]["track_only"] = True
        reg = registry(models, roster={"a/1": entry()})
        self.assertIn("a/4", score.candidates(reg, "h", TODAY, include_track_only=True))

    def test_dead_channel_excludes_native_entries(self):
        reg = registry(
            {"a/1": model(aa_coding=1), "b/1": model(aa_coding=2)},
            roster={"a/1": entry(harness="pi"), "b/1": entry(harness="claude-code")},
        )
        reg["hosts"]["h"]["channels"]["pi"] = False
        self.assertEqual(set(score.candidates(reg, "h", TODAY)), {"b/1"})

    def test_unknown_host_raises(self):
        reg = registry({"a/1": model(aa_coding=1)})
        with self.assertRaises(score.RegistryError):
            score.candidates(reg, "nope", TODAY)


class GeneralTiers(unittest.TestCase):
    def setUp(self):
        self.reg = registry(
            {
                "cheap/weak": model(aa_coding=10, p=0.05, c=0.1),
                "cheap/ok": model(
                    aa_coding=70, p=0.1, c=0.3
                ),  # norm 0.667: clears both floors
                "mid/good": model(aa_coding=80, p=1.0, c=3.0),
                "pricey/best": model(aa_coding=100, p=5.0, c=25.0),
            }
        )
        self.w = {"aa_coding": 1.0}

    def test_tier1_min_cost_above_floor(self):
        r = score.rank_general(self.reg, "h", TODAY, self.w, tier=1)
        self.assertEqual(r[0]["id"], "cheap/ok")

    def test_tier2_max_value(self):
        r = score.rank_general(self.reg, "h", TODAY, self.w, tier=2)
        self.assertEqual(r[0]["id"], "cheap/ok")
        self.assertGreater(r[0]["V"], r[1]["V"])

    def test_tier2_floor_excludes_cheap_weak_even_with_best_value(self):
        self.reg["models"]["cheap/ok"]["benchmarks"]["aa_coding"] = (
            50  # norm 0.444: T1 ok, T2 out
        )
        t1 = score.rank_general(self.reg, "h", TODAY, self.w, tier=1)
        t2 = score.rank_general(self.reg, "h", TODAY, self.w, tier=2)
        self.assertEqual(t1[0]["id"], "cheap/ok")
        self.assertEqual(t2[0]["id"], "mid/good")

    def test_tier4_frontier_includes_tier4_only_and_ignores_cost(self):
        self.reg["models"]["gated/top"] = model(aa_coding=120, p=50, c=250)
        self.reg["hosts"]["h"]["roster"]["gated/top"] = entry()
        self.reg["overrides"]["gated/top"] = {"constraints": {"tier_4_only": True}}
        t3 = score.rank_general(self.reg, "h", TODAY, self.w, tier=3)
        t4 = score.rank_general(self.reg, "h", TODAY, self.w, tier=4)
        self.assertNotIn("gated/top", [r["id"] for r in t3])
        self.assertEqual(t4[0]["id"], "gated/top")

    def test_tier3_max_quality_tie_prefers_cheaper(self):
        self.reg["models"]["mid/good"]["benchmarks"]["aa_coding"] = (
            99  # norm 0.989, within 0.02 of 1.0
        )
        r = score.rank_general(self.reg, "h", TODAY, self.w, tier=3)
        self.assertEqual(r[0]["id"], "mid/good")


class Pick(unittest.TestCase):
    def test_pick_returns_winner_with_execution_block(self):
        reg = registry(
            {
                "a/1": model(aa_coding=10, p=0.1, c=0.1),
                "a/2": model(aa_coding=90, p=1, c=1),
            }
        )
        reg["hosts"]["h"]["roster"]["a/2"]["execution"] = {
            "pi": {"channel": "native", "model_ref": "openrouter/a/2"}
        }
        reg["sources"]["aa_api"] = {
            "name": "x",
            "status": "failed",
            "as_of": None,
            "error": "boom",
        }
        got = score.pick(reg, "h", TODAY, "general", "coding", 3)
        self.assertEqual(got["id"], "a/2")
        self.assertEqual(got["execution"]["pi"]["model_ref"], "openrouter/a/2")
        self.assertEqual(got["runner_up"], "a/1")
        self.assertTrue(any("aa_api" in w for w in got["warnings"]))

    def test_pick_empty_rung_is_null_id(self):
        reg = registry(
            {
                "a/1": model(design_arena=1200, p=0.1, c=0.1),
                "a/2": model(design_arena=1300, p=1, c=1),
            }
        )
        got = score.pick(reg, "h", TODAY, "design", None, 3)
        self.assertIsNone(got["id"])


class DesignLadder(unittest.TestCase):
    def test_frontier_walk_spreads_over_four_rungs(self):
        reg = registry(
            {
                "a/1": model(design_arena=1252, p=0.065, c=0.18),
                "a/2": model(design_arena=1313, p=0.966, c=3.036),
                "a/3": model(design_arena=1314, p=0.75, c=3.75),
                "a/4": model(design_arena=1356, p=3, c=15),
                "a/5": model(design_arena=1320, p=5, c=25),  # dominated by a/4
                "a/6": model(design_arena=1135, p=1, c=1),  # dominated by a/2
            }
        )
        ladder = score.rank_design(reg, "h", TODAY)
        self.assertEqual([r["id"] for r in ladder[1]], ["a/1"])
        self.assertEqual(ladder[4][0]["id"], "a/4")
        self.assertNotIn("a/5", [r["id"] for t in ladder.values() for r in t])
        self.assertNotIn("a/6", [r["id"] for t in ladder.values() for r in t])
        picked = {t: [r["id"] for r in rs] for t, rs in ladder.items()}
        self.assertEqual(picked[2], ["a/2"])
        self.assertEqual(picked[3], ["a/3"])

    def test_three_frontier_points_leave_one_rung_empty(self):
        reg = registry(
            {
                "a/1": model(design_arena=1200, p=0.1, c=0.1),
                "a/2": model(design_arena=1300, p=1, c=1),
                "a/3": model(design_arena=1400, p=10, c=10),
            }
        )
        ladder = score.rank_design(reg, "h", TODAY)
        self.assertEqual(ladder[1][0]["id"], "a/1")
        self.assertEqual(ladder[4][0]["id"], "a/3")
        self.assertEqual(sum(1 for t in ladder.values() if not t), 1)


if __name__ == "__main__":
    unittest.main()
