"""Behaviour tests for refresh-benchmarks.py.  stdlib unittest, no network."""

import importlib.util
import json
import os
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent
spec = importlib.util.spec_from_file_location(
    "refresh", SCRIPTS / "refresh-benchmarks.py"
)
assert spec is not None and spec.loader is not None
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


def _load(path):
    with open(path) as f:
        return json.load(f)


def empty_reg():
    return refresh.empty_registry()


class DeriveMatch(unittest.TestCase):
    def test_openrouter_id_derives_all_feed_keys(self):
        m = refresh.derive_match("z-ai/glm-5.3-flash")
        self.assertEqual(m["openrouter"], "z-ai/glm-5.3-flash")
        self.assertEqual(m["aa_slug"], "glm-5-3-flash")
        self.assertIn("glm-5.3-flash", m["deepswe"])
        self.assertIn("z-ai/glm-5.3-flash", m["eqbench"])
        self.assertIn("glm-5.3-flash", m["eqbench"])
        self.assertIn("glm-5.3-flash", m["designarena"])
        self.assertIn("glm-5-3-flash", m["designarena"])

    def test_claude_id_strips_context_suffix(self):
        m = refresh.derive_match("anthropic/claude-fable-5-1[1m]")
        self.assertEqual(m["aa_slug"], "claude-fable-5-1")
        self.assertEqual(m["openrouter"], "anthropic/claude-fable-5-1")

    def test_override_patches_single_key(self):
        m = refresh.derive_match(
            "deepseek/deepseek-v4-flash-0731",
            override={"match": {"aa_slug": "deepseek-v4-flash"}},
        )
        self.assertEqual(m["aa_slug"], "deepseek-v4-flash")
        self.assertEqual(m["openrouter"], "deepseek/deepseek-v4-flash-0731")


class Roster(unittest.TestCase):
    def test_pi_roster_maps_openrouter_and_collapses_local(self):
        enabled = [
            "openrouter/z-ai/glm-5.3",
            "openrouter/openrouter/auto",
            "llama-swap/a-q4",
            "llama-swap/b-q8",
        ]
        roster = refresh.pi_roster_entries(enabled)
        self.assertIn("z-ai/glm-5.3", roster)
        self.assertNotIn("openrouter/auto", roster)
        self.assertIn("local/llama-swap", roster)
        self.assertTrue(roster["local/llama-swap"]["is_class_entry"])
        self.assertEqual(roster["local/llama-swap"]["count"], 2)
        self.assertEqual(
            roster["z-ai/glm-5.3"]["execution"]["pi"]["model_ref"],
            "openrouter/z-ai/glm-5.3",
        )
        self.assertEqual(roster["local/llama-swap"]["pricing"]["source"], "local")

    def test_probe_model_arg_uses_family_alias_unless_suffixed(self):
        self.assertEqual(refresh.probe_model_arg("anthropic/claude-haiku-4.5"), "haiku")
        self.assertEqual(
            refresh.probe_model_arg("anthropic/claude-fable-5-1[1m]"),
            "claude-fable-5-1[1m]",
        )

    def test_claude_entry_shape(self):
        e = refresh.claude_roster_entry("anthropic/claude-opus-5", ok=True)
        self.assertTrue(e["enabled"])
        self.assertEqual(e["execution"]["claude-code"]["model_param"], "opus")
        self.assertIn("claude-opus-5", e["execution"]["pi"]["command"])

    def test_missing_pi_disables_but_keeps_entries(self):
        old = {
            "z-ai/glm-5.3": refresh.pi_roster_entries(["openrouter/z-ai/glm-5.3"])[
                "z-ai/glm-5.3"
            ]
        }
        host = refresh.build_host(
            old_roster=old,
            pi_available=False,
            pi_entries=None,
            claude_available=False,
            claude_results=None,
            old_host=None,
            now="2026-09-06T00:00:00Z",
        )
        self.assertFalse(host["channels"]["pi"])
        self.assertIn("z-ai/glm-5.3", host["roster"])
        self.assertFalse(host["roster"]["z-ai/glm-5.3"]["enabled"])
        self.assertEqual(host["roster"]["z-ai/glm-5.3"]["note"], "pi-missing")

    def test_dropped_pi_model_marked_disabled_not_deleted(self):
        old = refresh.pi_roster_entries(
            ["openrouter/z-ai/glm-5.2", "openrouter/z-ai/glm-5.3"]
        )
        new = refresh.pi_roster_entries(["openrouter/z-ai/glm-5.3"])
        host = refresh.build_host(
            old_roster=old,
            pi_available=True,
            pi_entries=new,
            claude_available=False,
            claude_results=None,
            old_host=None,
            now="2026-09-06T00:00:00Z",
        )
        self.assertFalse(host["roster"]["z-ai/glm-5.2"]["enabled"])
        self.assertTrue(host["roster"]["z-ai/glm-5.3"]["enabled"])

    def test_probe_failure_keeps_prior_enabled(self):
        old = {
            "anthropic/claude-opus-5": refresh.claude_roster_entry(
                "anthropic/claude-opus-5", ok=True
            )
        }
        host = refresh.build_host(
            old_roster=old,
            pi_available=False,
            pi_entries=None,
            claude_available=True,
            claude_results=None,  # None = probe not run / failed
            old_host={"probed_with": {"claude": "2.1.0", "pi": None}},
            now="2026-09-06T00:00:00Z",
        )
        self.assertTrue(host["roster"]["anthropic/claude-opus-5"]["enabled"])
        self.assertEqual(host["probed_with"]["claude"], "2.1.0")


class Merge(unittest.TestCase):
    def setUp(self):
        self.reg = empty_reg()
        refresh.ensure_model(self.reg, "z-ai/glm-5.3")
        self.reg["models"]["z-ai/glm-5.3"]["benchmarks"]["aa_coding"] = 70.0
        self.reg["models"]["z-ai/glm-5.3"]["last_seen"]["aa_api"] = "2026-08-01"
        self.reg["sources"]["aa_api"] = refresh.source_stub("aa_api")
        self.reg["sources"]["aa_api"].update(status="ok", as_of="2026-08-01")

    def test_failed_source_keeps_values_and_as_of(self):
        changes = refresh.apply_feed(
            self.reg,
            "aa_api",
            refresh.FeedResult(error="boom"),
            today="2026-09-06",
            host="h",
        )
        self.assertEqual(changes, [])
        self.assertEqual(
            self.reg["models"]["z-ai/glm-5.3"]["benchmarks"]["aa_coding"], 70.0
        )
        self.assertEqual(self.reg["sources"]["aa_api"]["status"], "failed")
        self.assertEqual(self.reg["sources"]["aa_api"]["as_of"], "2026-08-01")
        self.assertEqual(self.reg["sources"]["aa_api"]["error"], "boom")

    def test_zero_matches_is_failure_not_truth(self):
        refresh.apply_feed(
            self.reg,
            "aa_api",
            refresh.FeedResult(values={}),
            today="2026-09-06",
            host="h",
        )
        self.assertEqual(self.reg["sources"]["aa_api"]["status"], "failed")
        self.assertEqual(
            self.reg["models"]["z-ai/glm-5.3"]["benchmarks"]["aa_coding"], 70.0
        )

    def test_absent_model_keeps_value_and_old_last_seen(self):
        refresh.ensure_model(self.reg, "x/other")
        res = refresh.FeedResult(values={"x/other": {"aa_coding": 10.0}})
        refresh.apply_feed(self.reg, "aa_api", res, today="2026-09-06", host="h")
        m = self.reg["models"]["z-ai/glm-5.3"]
        self.assertEqual(m["benchmarks"]["aa_coding"], 70.0)
        self.assertEqual(m["last_seen"]["aa_api"], "2026-08-01")
        self.assertEqual(
            self.reg["models"]["x/other"]["last_seen"]["aa_api"], "2026-09-06"
        )
        self.assertEqual(self.reg["sources"]["aa_api"]["status"], "ok")
        self.assertEqual(self.reg["sources"]["aa_api"]["as_of"], "2026-09-06")

    def test_present_model_updates_and_advances_last_seen(self):
        res = refresh.FeedResult(values={"z-ai/glm-5.3": {"aa_coding": 74.8}})
        changes = refresh.apply_feed(
            self.reg, "aa_api", res, today="2026-09-06", host="h"
        )
        self.assertEqual(
            self.reg["models"]["z-ai/glm-5.3"]["benchmarks"]["aa_coding"], 74.8
        )
        self.assertEqual(
            self.reg["models"]["z-ai/glm-5.3"]["last_seen"]["aa_api"], "2026-09-06"
        )
        self.assertTrue(any("aa_coding" in c for c in changes))

    def test_feed_never_writes_null_over_value(self):
        res = refresh.FeedResult(values={"z-ai/glm-5.3": {"aa_coding": None}})
        refresh.apply_feed(self.reg, "aa_api", res, today="2026-09-06", host="h")
        self.assertEqual(
            self.reg["models"]["z-ai/glm-5.3"]["benchmarks"]["aa_coding"], 70.0
        )

    def test_elo_drift_below_threshold_ignored(self):
        self.reg["models"]["z-ai/glm-5.3"]["benchmarks"]["design_arena"] = 1300
        res = refresh.FeedResult(values={"z-ai/glm-5.3": {"design_arena": 1305}})
        changes = refresh.apply_feed(
            self.reg, "design_arena", res, today="2026-09-06", host="h"
        )
        self.assertEqual(
            self.reg["models"]["z-ai/glm-5.3"]["benchmarks"]["design_arena"], 1300
        )
        self.assertEqual(changes, [])

    def test_pricing_written_with_source(self):
        res = refresh.FeedResult(
            values={
                "z-ai/glm-5.3": {
                    "pricing": {"prompt_cost_per_m": 1.4, "completion_cost_per_m": 4.4},
                    "context_window": 1310720,
                }
            }
        )
        refresh.apply_feed(self.reg, "openrouter", res, today="2026-09-06", host="h")
        p = self.reg["models"]["z-ai/glm-5.3"]["pricing"]
        self.assertEqual(p["source"], "openrouter")
        self.assertEqual(p["prompt_cost_per_m"], 1.4)
        self.assertEqual(self.reg["models"]["z-ai/glm-5.3"]["context_window"], 1310720)

    def test_aa_pricing_does_not_override_openrouter(self):
        m = self.reg["models"]["z-ai/glm-5.3"]
        m["pricing"] = {
            "prompt_cost_per_m": 1.4,
            "completion_cost_per_m": 4.4,
            "source": "openrouter",
        }
        res = refresh.FeedResult(
            values={
                "z-ai/glm-5.3": {
                    "pricing": {"prompt_cost_per_m": 9, "completion_cost_per_m": 9}
                }
            }
        )
        refresh.apply_feed(self.reg, "aa_api", res, today="2026-09-06", host="h")
        self.assertEqual(m["pricing"]["prompt_cost_per_m"], 1.4)


class Parsers(unittest.TestCase):
    def test_omniscience_flight_parse_inverts_hallucination(self):
        html = (
            '<script>self.__next_f.push([1,"{\\"slug\\":\\"glm-5-3\\",\\"name\\":\\"GLM-5.3 (max)\\","])'
            '</script><script>self.__next_f.push([1,"\\"omniscience\\":14.3,\\"omniscienceBreakdown\\":'
            '{\\"accuracy\\":0.5,\\"hallucinationRate\\":0.25}"])</script>'
        )
        rows = refresh.parse_omniscience(html)
        self.assertAlmostEqual(rows["glm-5-3"]["aa_omniscience"], 14.3)
        self.assertAlmostEqual(rows["glm-5-3"]["aa_factuality"], 0.75)

    def test_aa_api_rows(self):
        data = {
            "data": [
                {
                    "slug": "glm-5-3",
                    "name": "GLM-5.3",
                    "evaluations": {
                        "artificial_analysis_intelligence_index": 48.6,
                        "artificial_analysis_coding_index": 74.8,
                        "terminalbench_v2_1": 0.8,
                    },
                    "pricing": {
                        "price_1m_input_tokens": 1.4,
                        "price_1m_output_tokens": 4.4,
                    },
                }
            ]
        }
        rows = refresh.parse_aa_api(data)
        self.assertEqual(rows["glm-5-3"]["aa_intelligence"], 48.6)
        self.assertEqual(rows["glm-5-3"]["terminal_bench"], 80.0)
        self.assertEqual(rows["glm-5-3"]["pricing"]["prompt_cost_per_m"], 1.4)

    def test_openrouter_rows_skip_negative(self):
        data = {
            "data": [
                {
                    "id": "z-ai/glm-5.3",
                    "context_length": 100,
                    "pricing": {"prompt": "0.0000014", "completion": "0.0000044"},
                },
                {
                    "id": "openrouter/auto",
                    "context_length": 1,
                    "pricing": {"prompt": "-1", "completion": "-1"},
                },
            ]
        }
        rows = refresh.parse_openrouter(data)
        self.assertEqual(rows["z-ai/glm-5.3"]["pricing"]["prompt_cost_per_m"], 1.4)
        self.assertEqual(rows["z-ai/glm-5.3"]["context_window"], 100)
        self.assertNotIn("openrouter/auto", rows)

    def test_deepswe_rows(self):
        html = (
            "<tr><td>glm-5.3</td><td><span>[</span><span>max</span><span>]</span></td><td><b>74</b><i>%</i><s>±</s><s>3</s></td></tr>"
            "<tr><td>kimi-k3</td><td><b>70.5</b><i>%</i></td></tr>"
            "<tr><td>glm-5.3</td><td><b>60</b><i>%</i></td></tr>"
        )  # later all-efforts row must not override
        rows = refresh.parse_deepswe(html)
        self.assertEqual(rows["glm-5.3"], 74.0)
        self.assertEqual(rows["kimi-k3"], 70.5)

    def test_match_rows_by_feed_key(self):
        reg = empty_reg()
        refresh.ensure_model(reg, "moonshotai/kimi-k3")
        rows = {"kimi-k3": 1356}
        out = refresh.match_feed(reg, "designarena", rows)
        self.assertEqual(out, {"moonshotai/kimi-k3": 1356})


class Overrides(unittest.TestCase):
    def test_track_only_creates_model_without_roster(self):
        reg = empty_reg()
        reg["overrides"]["meta/muse-spark-1.3"] = {"track_only": True}
        refresh.apply_overrides(reg)
        self.assertIn("meta/muse-spark-1.3", reg["models"])
        self.assertTrue(reg["models"]["meta/muse-spark-1.3"]["track_only"])

    def test_override_match_and_notes_land_on_model(self):
        reg = empty_reg()
        refresh.ensure_model(reg, "deepseek/deepseek-v4-flash-0731")
        reg["overrides"]["deepseek/deepseek-v4-flash-0731"] = {
            "match": {"aa_slug": "deepseek-v4-flash"},
            "benchmark_notes": {"aa_slug": "AA aliases 0731"},
        }
        refresh.apply_overrides(reg)
        m = reg["models"]["deepseek/deepseek-v4-flash-0731"]
        self.assertEqual(m["match"]["aa_slug"], "deepseek-v4-flash")
        self.assertEqual(m["benchmark_notes"]["aa_slug"], "AA aliases 0731")


class Gates(unittest.TestCase):
    def test_validate_accepts_minimal_registry(self):
        reg = empty_reg()
        reg["updated_at"] = "2026-09-06T00:00:00Z"
        errs = refresh.validate(reg)
        self.assertEqual(errs, [])

    def test_validate_rejects_negative_price(self):
        reg = empty_reg()
        reg["updated_at"] = "2026-09-06T00:00:00Z"
        refresh.ensure_model(reg, "z-ai/glm-5.3")
        reg["models"]["z-ai/glm-5.3"]["pricing"]["prompt_cost_per_m"] = -1
        self.assertTrue(refresh.validate(reg))

    def test_validate_rejects_unknown_benchmark_key(self):
        reg = empty_reg()
        reg["updated_at"] = "2026-09-06T00:00:00Z"
        refresh.ensure_model(reg, "z-ai/glm-5.3")
        reg["models"]["z-ai/glm-5.3"]["benchmarks"]["aa-coding"] = 1
        self.assertTrue(refresh.validate(reg))

    def test_critical_missing_roster_refuses_write(self):
        reg = empty_reg()
        reg["hosts"]["h"] = {
            "probed_at": "2026-09-06T00:00:00Z",
            "probed_with": {},
            "channels": {"pi": False, "claude-code": False},
            "roster": {},
        }
        self.assertFalse(refresh.critical_ok(reg, "h"))

    def test_write_is_atomic_with_backup(self):
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.json")
            reg = empty_reg()
            reg["updated_at"] = "2026-09-06T00:00:00Z"
            refresh.write_registry(reg, p)
            reg["updated_at"] = "2026-09-07T00:00:00Z"
            refresh.write_registry(reg, p)
            self.assertTrue(os.path.exists(p + ".bak"))
            self.assertEqual(_load(p + ".bak")["updated_at"], "2026-09-06T00:00:00Z")
            self.assertEqual(_load(p)["updated_at"], "2026-09-07T00:00:00Z")


if __name__ == "__main__":
    unittest.main()
