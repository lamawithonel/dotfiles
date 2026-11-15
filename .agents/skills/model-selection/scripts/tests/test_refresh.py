#!/usr/bin/env python3
"""Behaviour tests for refresh-benchmarks.py (registry v4).  Offline, stdlib only.

Fixtures under tests/fixtures are trimmed from real bytes fetched 2026-11-09.
"""

import copy
import email.utils
import http.client
import importlib.util
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from typing import Any
from unittest import mock

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent
FIX = HERE.parents[1] / "assets" / "fixtures"
sys.path.insert(0, str(SCRIPTS))

import boards
import registry

spec = importlib.util.spec_from_file_location(
    "refresh", SCRIPTS / "refresh-benchmarks.py"
)
assert spec is not None and spec.loader is not None
refresh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(refresh)


def setUpModule() -> None:
    # Feeds log progress to stderr; a passing run prints only the summary.
    patcher = mock.patch.object(refresh, "log")
    patcher.start()
    unittest.addModuleCleanup(patcher.stop)
    # Never touch the real Arena cache or a real token, whatever the host has.
    cache = tempfile.TemporaryDirectory()
    unittest.addModuleCleanup(cache.cleanup)
    env = mock.patch.dict(os.environ, {"XDG_CACHE_HOME": cache.name})
    env.start()
    unittest.addModuleCleanup(env.stop)
    os.environ.pop("HF_TOKEN", None)


# Rows each parser saw on 2026-11-09 (full pages, not the trimmed fixtures).
TODAY_ROWS = {
    "openrouter": 454,
    "aa_free": 727,
    "aa_page_lcr": 28,
    "aa_page_cyber": 25,
    "aa_page_healthbench": 14,
    "aa_page_3d": 25,
    "aa_omniscience": 28,
}
TODAY = "2026-11-09"


def read(name: str) -> str:
    return (FIX / name).read_text(encoding="utf-8")


def jread(name: str) -> Any:
    return json.loads(read(name))


def v4_reg() -> dict[str, Any]:
    """A minimal valid v4 registry with a hand-owned policy and overrides."""
    return {
        "schema_version": 4,
        "updated_at": "2026-11-01T00:00:00Z",
        "notes": ["test"],
        "policy": {
            "bands": {
                "order": ["bulk", "haiku", "sonnet", "opus", "mythos"],
                "floors": {"bulk": 20.9, "haiku": 28.4, "sonnet": 39.4, "opus": 49.2},
                "mythos": ["anthropic/claude-fable-5-1[1m]"],
            },
            "cost": {"blend": {"input": 0.75, "output": 0.25}},
        },
        "overrides": {
            "z-ai/glm-5.3": {
                "placements": {"xhigh": {"aai": 33.0, "confidence": "low"}}
            }
        },
        "models": {},
        "hosts": {},
        "sources": {},
    }


def aa_rows() -> list[dict[str, Any]]:
    return jread("aa_free_p1.json")["data"] + jread("aa_free_p2.json")["data"]


class Effort(unittest.TestCase):
    def test_slug_suffix_agrees_with_name(self):
        self.assertEqual(
            refresh.aa_effort(
                "claude-sonnet-5-5-high", "Claude Sonnet 5.5 (High, Default Fallback)"
            ),
            ("claude-sonnet-5-5", "high"),
        )

    def test_name_only_effort_keeps_slug_as_base(self):
        self.assertEqual(
            refresh.aa_effort("gpt-6-astra", "GPT-6 Astra (Max)"),
            ("gpt-6-astra", "max"),
        )

    def test_non_reasoning_suffix_is_off(self):
        self.assertEqual(
            refresh.aa_effort(
                "gpt-6-1-terra-non-reasoning", "GPT-6.1 Terra (Non-reasoning)"
            ),
            ("gpt-6-1-terra", "off"),
        )

    def test_no_marker_is_single(self):
        self.assertEqual(
            refresh.aa_effort("glm-5-3-flash", "GLM-5.3-Flash"),
            ("glm-5-3-flash", "single"),
        )

    def test_model_named_max_is_not_an_effort(self):
        self.assertEqual(
            refresh.aa_effort("qwen3-max", "Qwen3 Max"), ("qwen3-max", "single")
        )

    def test_explicit_effort_beats_non_reasoning_token(self):
        self.assertEqual(
            refresh.aa_effort(
                "claude-opus-4-7-non-reasoning", "Claude Opus 4.7 (Non-reasoning, High)"
            ),
            ("claude-opus-4-7-non-reasoning", "high"),
        )

    def test_comma_list_picks_effort_token(self):
        self.assertEqual(
            refresh.aa_effort(
                "gpt-6-sol-daybreak-blue", "GPT-6 Sol (Daybreak Blue, max)"
            ),
            ("gpt-6-sol-daybreak-blue", "max"),
        )


class AaFree(unittest.TestCase):
    def test_below_min_rows_raises(self):
        with self.assertRaises(refresh.FeedMinRowsError):
            refresh.parse_aa_free([jread("aa_free_p1.json")])

    def test_variants_by_base_and_effort(self):
        rows = refresh.parse_aa_free(
            [jread("aa_free_p1.json"), jread("aa_free_p2.json")], min_rows=1
        )
        sonnet = rows["claude-sonnet-5-5"]
        self.assertEqual(set(sonnet), {"high", "medium"})
        self.assertEqual(sonnet["high"]["aai"], 41.5)
        self.assertEqual(sonnet["high"]["index_cost_usd"], 1268.3)
        self.assertEqual(sonnet["high"]["aa_slug"], "claude-sonnet-5-5-high")
        self.assertEqual(set(rows["gpt-6-astra"]), {"max", "xhigh"})
        self.assertIn("single", rows["glm-5-3-flash"])
        self.assertIn("off", rows["gpt-6-1-terra"])

    def test_domains_and_business_mean(self):
        rows = refresh.parse_aa_free([jread("aa_free_p1.json")], min_rows=1)
        dom = rows["claude-sonnet-5-5"]["medium"]["domains"]
        self.assertEqual(dom["fin_acct"], 40.7)
        self.assertEqual(dom["strat_ops"], 46.7)
        self.assertEqual(dom["legal"], 38.8)
        self.assertEqual(dom["health_med"], 40.2)
        self.assertEqual(dom["economics"], 39.2)
        self.assertAlmostEqual(dom["business"], (40.7 + 46.7 + 38.8 + 39.2) / 4, 2)

    def test_pricing_comes_from_aa(self):
        rows = refresh.parse_aa_free([jread("aa_free_p1.json")], min_rows=1)
        price = rows["claude-sonnet-5-5"]["high"]["aa_pricing"]
        self.assertEqual(price, {"input": 2, "output": 10})

    def test_unscored_rows_are_skipped(self):
        rows = refresh.parse_aa_free([jread("aa_free_p1.json")], min_rows=1)
        self.assertNotIn("glm-4-5v", rows)

    def test_min_rows_is_below_today_and_not_trivial(self):
        min_rows = refresh.MIN_ROWS["aa_free"]
        self.assertLessEqual(min_rows, TODAY_ROWS["aa_free"])
        self.assertGreaterEqual(min_rows, TODAY_ROWS["aa_free"] // 2)

    def test_key_only_travels_in_header(self):
        self.assertNotIn("api_key", refresh.AA_FREE_URL.lower())
        self.assertNotIn("x-api-key", refresh.AA_FREE_URL.lower())


class Pages(unittest.TestCase):
    def test_lcr_page_has_tb4_and_lcr(self):
        rows = refresh.parse_page(
            read("aa_page_lcr.html"), refresh.PAGE_SPECS["aa_page_lcr"], min_rows=1
        )
        opus = rows["claude-opus-5-5"]["max"]
        self.assertAlmostEqual(opus["tb4"], 0.595959595959596)
        self.assertAlmostEqual(opus["lcr"], 0.846666666666667)
        self.assertEqual(
            set(rows),
            {
                "claude-opus-5-5",
                "claude-sonnet-5-5",
                "gpt-6-astra",
                "claude-haiku-5-5",
                "kimi-k3-1-pro",
            },
        )
        self.assertIn("single", rows["kimi-k3-1-pro"])

    def test_cyber_page(self):
        rows = refresh.parse_page(
            read("aa_page_cyber.html"), refresh.PAGE_SPECS["aa_page_cyber"], min_rows=1
        )
        self.assertAlmostEqual(rows["gpt-6-astra"]["max"]["aa_cyber"], 33.4198270126414)
        self.assertEqual(set(rows["gpt-6-astra"]["max"]), {"aa_cyber"})

    def test_healthbench_page(self):
        rows = refresh.parse_page(
            read("aa_page_healthbench.html"),
            refresh.PAGE_SPECS["aa_page_healthbench"],
            min_rows=1,
        )
        self.assertAlmostEqual(
            rows["claude-sonnet-5-5"]["max"]["healthbench"], 0.620657287652967
        )

    def test_page_below_min_rows_raises(self):
        with self.assertRaises(refresh.FeedMinRowsError):
            refresh.parse_page(
                read("aa_page_cyber.html"), refresh.PAGE_SPECS["aa_page_cyber"]
            )

    def test_page_keeps_only_listed_fields(self):
        rows = refresh.parse_page(
            read("aa_page_lcr.html"), refresh.PAGE_SPECS["aa_page_lcr"], min_rows=1
        )
        for efforts in rows.values():
            for vals in efforts.values():
                self.assertLessEqual(set(vals), {"tb4", "lcr"})

    def test_aa3d_score_and_interval(self):
        rows = refresh.parse_aa3d(read("aa_page_3d.html"), min_rows=1)
        opus = rows["claude-opus-5-5"]["max"]
        self.assertAlmostEqual(opus["score"], 1202.4312)
        self.assertAlmostEqual(opus["ci"], (1230.739 - 1174.1234) / 2, 2)
        self.assertIn("single", rows["kimi-k3-1-pro"])

    def test_aa3d_below_min_rows_raises(self):
        with self.assertRaises(refresh.FeedMinRowsError):
            refresh.parse_aa3d(read("aa_page_3d.html"))

    def test_omniscience_inverts_hallucination(self):
        rows = refresh.parse_omniscience(read("aa_page_omniscience.html"), min_rows=1)
        carbon = rows["gemini-4-carbon"]["high"]
        self.assertAlmostEqual(carbon["omniscience"], 53.5)
        self.assertAlmostEqual(carbon["factuality"], 1 - 0.10655737704918032, 4)
        self.assertIn("max", rows["claude-fable-5-2"])

    def test_omniscience_below_min_rows_raises(self):
        with self.assertRaises(refresh.FeedMinRowsError):
            refresh.parse_omniscience(read("aa_page_omniscience.html"))

    def test_min_rows_sit_below_today_and_above_half(self):
        for feed, today in TODAY_ROWS.items():
            min_rows = refresh.MIN_ROWS[feed]
            self.assertLessEqual(min_rows, today, feed)
            self.assertGreaterEqual(min_rows, today // 2, feed)


OR_DATA = {
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


class OpenRouter(unittest.TestCase):
    def test_rows_skip_negative_and_scale_per_million(self):
        rows = refresh.parse_openrouter(OR_DATA, min_rows=1)
        self.assertEqual(rows["z-ai/glm-5.3"], {"input": 1.4, "output": 4.4})
        self.assertNotIn("openrouter/auto", rows)

    def test_below_min_rows_raises(self):
        with self.assertRaises(refresh.FeedMinRowsError):
            refresh.parse_openrouter(OR_DATA)

    def test_fable_override_matches_real_openrouter_id(self):
        m = refresh.derive_match("anthropic/claude-fable-5-1[1m]")
        self.assertEqual(m["openrouter"], "anthropic/claude-fable-5.1")
        self.assertEqual(m["aa_slug"], "claude-fable-5-1")

    def test_fable_gets_openrouter_price(self):
        reg = v4_reg()
        mid = "anthropic/claude-fable-5-1[1m]"
        refresh.ensure_model(reg, mid)
        refresh.apply_overrides(reg)
        rows = {"anthropic/claude-fable-5.1": {"input": 5.0, "output": 25.0}}
        got = refresh.match_feed(reg, "openrouter", rows)
        self.assertEqual(got, {mid: rows["anthropic/claude-fable-5.1"]})

    def test_hand_override_can_still_patch_match(self):
        m = refresh.derive_match(
            "anthropic/claude-fable-5-1[1m]",
            override={"match": {"openrouter": "anthropic/other"}},
        )
        self.assertEqual(m["openrouter"], "anthropic/other")


class OpenRouterKey(unittest.TestCase):
    """The key's own prices, reread from Pi's models store each refresh."""

    def setUp(self):
        self.store = jread("pi_models_store.json")["openrouter"]["models"]

    def test_store_cost_becomes_a_key_price(self):
        rows = refresh.parse_key_prices(self.store, min_rows=1)
        self.assertEqual(
            rows["z-ai/glm-5.3"],
            {"input": 0.84, "output": 2.64, "source": "openrouter-key"},
        )

    def test_router_alias_and_free_twins_are_not_prices(self):
        store = [*self.store, {"id": "qwen/q:free", "cost": {"input": 0, "output": 0}}]
        rows = refresh.parse_key_prices(store, min_rows=1)
        self.assertNotIn("openrouter/auto", rows)
        self.assertNotIn("qwen/q:free", rows)

    def test_below_min_rows_raises(self):
        self.assertIn("openrouter_key", refresh.FEEDS)
        with self.assertRaises(refresh.FeedMinRowsError):
            refresh.parse_key_prices(self.store)

    def test_missing_store_fails_the_feed_and_keeps_prices(self):
        reg = v4_reg()
        mid = "z-ai/glm-5.3"
        refresh.ensure_model(reg, mid)
        old = {"input": 0.84, "output": 2.64, "source": "openrouter-key"}
        reg["models"][mid]["pricing"] = dict(old)
        feeds = {"openrouter_key": refresh.feed_openrouter_key}
        with tempfile.TemporaryDirectory() as tmp:
            gone = os.path.join(tmp, "models-store.json")
            with (
                mock.patch.object(refresh, "PI_STORE", gone),
                mock.patch.object(refresh, "log"),
            ):
                refresh.run_feeds(reg, feeds, [], TODAY, "h", {})
        self.assertEqual(reg["sources"]["openrouter_key"]["status"], "failed")
        self.assertEqual(reg["models"][mid]["pricing"], old)


class PiRoster(unittest.TestCase):
    def setUp(self):
        self.enabled = jread("pi_settings.json")["enabledModels"]
        self.store = jread("pi_models_store.json")["openrouter"]
        self.roster = refresh.pi_roster_entries(self.enabled, self.store["models"])

    def test_auto_and_local_are_skipped(self):
        self.assertNotIn("openrouter/auto", self.roster)
        self.assertFalse(
            any(k.startswith(("llama-swap", "local/")) for k in self.roster)
        )

    def test_zdr_needs_enabled_and_store_membership(self):
        glm = self.roster["z-ai/glm-5.3"]
        self.assertEqual(glm["rosters"], ["pi-zdr", "pi-enabled"])
        self.assertEqual(glm["harness"], "pi")
        self.assertTrue(glm["enabled"])
        self.assertEqual(glm["model_ref"], "openrouter/z-ai/glm-5.3")
        self.assertIsNone(glm["model_param"])
        self.assertEqual(
            self.roster["meta/muse-glimmer-30b"]["rosters"], ["pi-enabled"]
        )

    def test_price_and_context_from_store(self):
        glm = self.roster["z-ai/glm-5.3"]
        self.assertEqual(glm["price"], {"input": 0.84, "output": 2.64})
        self.assertEqual(glm["context_window"], 1048576)
        self.assertIsNone(self.roster["meta/muse-glimmer-30b"]["price"])

    def test_pi_levels_are_non_null_map_keys(self):
        self.assertEqual(
            self.roster["z-ai/glm-5.3"]["pi_levels"], ["low", "high", "max"]
        )
        self.assertEqual(
            self.roster["deepseek/deepseek-v4.1-flash"]["pi_levels"],
            ["off", "low", "high", "max"],
        )

    def test_reasoning_without_map_gets_pi_default_levels(self):
        self.assertEqual(
            self.roster["minimax/minimax-m3"]["pi_levels"],
            ["off", "minimal", "low", "medium", "high"],
        )

    def test_non_reasoning_without_map_is_off_only(self):
        store = [
            {
                "id": "x/plain",
                "reasoning": False,
                "thinkingLevelMap": None,
                "cost": {"input": 1, "output": 2},
            }
        ]
        roster = refresh.pi_roster_entries(["openrouter/x/plain"], store)
        self.assertEqual(roster["x/plain"]["pi_levels"], ["off"])

    def test_not_in_store_has_empty_levels(self):
        self.assertEqual(self.roster["meta/muse-glimmer-30b"]["pi_levels"], [])

    def test_free_suffix_is_stripped_and_paid_wins(self):
        gemma = self.roster["google/gemma-4-31b-it"]
        self.assertEqual(gemma["model_ref"], "openrouter/google/gemma-4-31b-it")
        self.assertEqual(gemma["rosters"], ["pi-zdr", "pi-enabled"])
        self.assertNotIn("google/gemma-4-31b-it:free", self.roster)

    def test_free_only_entry_is_not_zdr(self):
        e = self.roster["google/gemma-4-26b-a4b-it"]
        self.assertEqual(e["rosters"], ["pi-enabled"])
        self.assertEqual(e["model_ref"], "openrouter/google/gemma-4-26b-a4b-it:free")

    def test_thinking_suffix_is_stripped_from_ref(self):
        e = self.roster["qwen/qwen3.6-35b-a3b"]
        self.assertEqual(e["model_ref"], "openrouter/qwen/qwen3.6-35b-a3b")
        self.assertEqual(e["rosters"], ["pi-zdr", "pi-enabled"])

    def test_store_meta(self):
        meta = refresh.store_meta(self.store)
        self.assertEqual(meta["count"], len(self.store["models"]))
        self.assertEqual(meta["checked_at"], "2026-11-09T15:41:48Z")

    def test_dropped_pi_model_is_disabled_not_deleted(self):
        old = {"roster": {"old/model": dict(self.roster["z-ai/glm-5.3"])}}
        host = refresh.build_host(
            old,
            pi_available=True,
            pi_entries=self.roster,
            pi_meta={"checked_at": "x", "count": 1},
            claude_available=False,
            claude_results=None,
            now="2026-11-09T00:00:00Z",
        )
        self.assertFalse(host["roster"]["old/model"]["enabled"])
        self.assertTrue(host["roster"]["z-ai/glm-5.3"]["enabled"])
        self.assertEqual(host["pi_models_store"]["count"], 1)
        self.assertEqual(host["default_profile"], "claude-code")
        self.assertEqual(host["herdr"], "env")

    def test_probe_failure_keeps_prior_claude_entry(self):
        entry = refresh.claude_roster_entry("anthropic/claude-opus-5.5", ok=True)
        host = refresh.build_host(
            {"roster": {"anthropic/claude-opus-5.5": entry}},
            pi_available=False,
            pi_entries=None,
            pi_meta=None,
            claude_available=True,
            claude_results=None,
            now="2026-11-09T00:00:00Z",
        )
        self.assertTrue(host["roster"]["anthropic/claude-opus-5.5"]["enabled"])
        self.assertEqual(entry["harness"], "claude-code")
        self.assertEqual(entry["model_param"], "opus")


class Merge(unittest.TestCase):
    def setUp(self):
        self.reg = v4_reg()
        self.mid = "anthropic/claude-sonnet-5.5"
        refresh.ensure_model(self.reg, self.mid)
        self.reg["models"][self.mid]["variants"]["high"] = refresh.variant_stub()
        self.reg["models"][self.mid]["variants"]["high"]["aai"] = 41.5
        self.reg["sources"]["aa_free"] = {"status": "ok", "as_of": "2026-11-01"}

    def test_failed_feed_keeps_old_values(self):
        refresh.apply_feed(
            self.reg, "aa_free", refresh.FeedResult(error="boom"), TODAY, "h"
        )
        self.assertEqual(self.reg["models"][self.mid]["variants"]["high"]["aai"], 41.5)
        src = self.reg["sources"]["aa_free"]
        self.assertEqual(src["status"], "failed")
        self.assertEqual(src["as_of"], "2026-11-01")
        self.assertEqual(src["error"], "boom")

    def test_min_rows_error_becomes_failed_feed_keeping_values(self):
        def feed(_reg, _cache):
            return refresh.parse_aa_free(
                [jread("aa_free_p1.json")]
            )  # below the row minimum

        changes = refresh.run_feeds(self.reg, {"aa_free": feed}, [], TODAY, "h", {})
        self.assertEqual(changes, [])
        self.assertEqual(self.reg["sources"]["aa_free"]["status"], "failed")
        self.assertIn("minimum", self.reg["sources"]["aa_free"]["error"])
        self.assertEqual(self.reg["models"][self.mid]["variants"]["high"]["aai"], 41.5)

    def test_zero_matches_is_failure(self):
        refresh.apply_feed(
            self.reg, "aa_free", refresh.FeedResult(values={}), TODAY, "h"
        )
        self.assertEqual(self.reg["sources"]["aa_free"]["status"], "failed")

    def test_null_never_overwrites_value(self):
        res = refresh.FeedResult(
            values={
                self.mid: {"variants": {"high": {"aai": None, "page": {"tb4": None}}}}
            }
        )
        refresh.apply_feed(self.reg, "aa_free", res, TODAY, "h")
        self.assertEqual(self.reg["models"][self.mid]["variants"]["high"]["aai"], 41.5)

    def test_variant_update_records_change_and_last_seen(self):
        res = refresh.FeedResult(
            values={
                self.mid: {"variants": {"high": {"aai": 42.0, "index_cost_usd": 9.0}}}
            },
            rows=700,
        )
        changes = refresh.apply_feed(self.reg, "aa_free", res, TODAY, "h")
        m = self.reg["models"][self.mid]
        self.assertEqual(m["variants"]["high"]["aai"], 42.0)
        self.assertEqual(m["variants"]["high"]["aai_source"], "aa_free")
        self.assertEqual(m["last_seen"]["aa_free"], TODAY)
        self.assertTrue(any("aai" in c for c in changes))
        self.assertEqual(self.reg["sources"]["aa_free"]["rows"], 700)

    def test_page_fields_and_domains_merge_without_clobbering(self):
        refresh.apply_feed(
            self.reg,
            "aa_page_lcr",
            refresh.FeedResult(
                values={self.mid: {"variants": {"max": {"page": {"tb4": 0.63}}}}}
            ),
            TODAY,
            "h",
        )
        refresh.apply_feed(
            self.reg,
            "aa_page_cyber",
            refresh.FeedResult(
                values={self.mid: {"variants": {"max": {"page": {"aa_cyber": 3.0}}}}}
            ),
            TODAY,
            "h",
        )
        page = self.reg["models"][self.mid]["variants"]["max"]["page"]
        self.assertEqual((page["tb4"], page["aa_cyber"]), (0.63, 3.0))

    def test_board_entry_gets_as_of_and_damps_elo_jitter(self):
        entry = {"score": 1300.0, "ci": 5.0, "effort": None, "votes": None}
        res = refresh.FeedResult(values={self.mid: {"boards": {"eq_bench": entry}}})
        refresh.apply_feed(self.reg, "eq_bench", res, TODAY, "h")
        got = self.reg["models"][self.mid]["boards"]["eq_bench"]
        self.assertEqual((got["score"], got["as_of"]), (1300.0, TODAY))
        res = refresh.FeedResult(
            values={self.mid: {"boards": {"eq_bench": {**entry, "score": 1303.0}}}}
        )
        changes = refresh.apply_feed(self.reg, "eq_bench", res, "2026-11-10", "h")
        self.assertEqual(
            self.reg["models"][self.mid]["boards"]["eq_bench"]["score"], 1300.0
        )
        self.assertEqual(changes, [])

    def test_aa_pricing_stored_and_openrouter_price_wins(self):
        refresh.apply_feed(
            self.reg,
            "openrouter",
            refresh.FeedResult(
                values={self.mid: {"pricing": {"input": 3.0, "output": 15.0}}}
            ),
            TODAY,
            "h",
        )
        refresh.apply_feed(
            self.reg,
            "aa_free",
            refresh.FeedResult(
                values={
                    self.mid: {
                        "aa_pricing": {"input": 2, "output": 10},
                        "pricing": {"input": 9.0, "output": 9.0},
                    }
                }
            ),
            TODAY,
            "h",
        )
        m = self.reg["models"][self.mid]
        self.assertEqual(
            m["pricing"], {"input": 3.0, "output": 15.0, "source": "openrouter"}
        )
        self.assertEqual(m["aa_pricing"], {"input": 2, "output": 10})

    def price(self, feed: str, i: float, o: float, **extra: Any) -> list[str]:
        vals = {self.mid: {"pricing": {"input": i, "output": o, **extra}}}
        res = refresh.FeedResult(values=vals)
        return refresh.apply_feed(self.reg, feed, res, TODAY, "h")

    def key_price(self, i: float, o: float) -> list[str]:
        return self.price("openrouter_key", i, o, source="openrouter-key")

    def test_openrouter_never_overwrites_a_key_price(self):
        self.key_price(0.84, 2.64)
        self.assertEqual(self.price("openrouter", 0.07, 1.4), [])
        self.assertEqual(
            self.reg["models"][self.mid]["pricing"],
            {"input": 0.84, "output": 2.64, "source": "openrouter-key"},
        )

    def test_key_price_restores_over_an_openrouter_price(self):
        self.price("openrouter", 0.07, 1.4)
        changes = self.key_price(0.84, 2.64)
        self.assertEqual(
            self.reg["models"][self.mid]["pricing"]["source"], "openrouter-key"
        )
        self.assertEqual(
            changes,
            [
                f"{self.mid}.pricing: 0.07/1.4 (openrouter) -> 0.84/2.64 (openrouter-key)"
            ],
        )

    def test_change_line_shows_source_and_plain_numbers(self):
        self.reg["models"][self.mid]["pricing"] = {
            "input": 4,
            "output": 20,
            "source": "aa_free",
        }
        changes = self.price("openrouter", 4.0, 20.0)
        self.assertEqual(
            changes, [f"{self.mid}.pricing: 4/20 (aa_free) -> 4/20 (openrouter)"]
        )

    def test_int_versus_float_with_same_source_is_not_a_change(self):
        self.reg["models"][self.mid]["pricing"] = {
            "input": 4,
            "output": 20,
            "source": "openrouter",
        }
        self.assertEqual(self.price("openrouter", 4.0, 20.0), [])


class Boards(unittest.TestCase):
    def test_every_board_is_registered_with_boards_min_rows(self):
        for board in boards.FETCH:
            self.assertIn(board, refresh.FEEDS)
            self.assertEqual(refresh.MIN_ROWS[board], boards.MIN_ROWS[board])
        self.assertIn("arena_lang_mean", refresh.FEEDS)
        self.assertIn("arena_european_mean", refresh.FEEDS)

    def test_match_board_picks_best_row_across_efforts(self):
        reg = v4_reg()
        mid = "anthropic/claude-opus-5.5"
        refresh.ensure_model(reg, mid)
        refresh.apply_overrides(reg)
        rows = [
            {
                "key": "claude-opus-5.5",
                "score": 1700.0,
                "ci": 9.0,
                "effort": "high",
                "votes": 10,
            },
            {
                "key": "claude-opus-5-5",
                "score": 1818.0,
                "ci": 12.0,
                "effort": "max",
                "votes": 20,
            },
            {
                "key": "other",
                "score": 2000.0,
                "ci": None,
                "effort": None,
                "votes": None,
            },
        ]
        got = refresh.match_board(reg, rows)
        self.assertEqual(got[mid]["score"], 1818.0)
        self.assertEqual(got[mid]["effort"], "max")

    def test_match_board_matches_arena_display_names(self):
        # Live Arena rows carry display names: "Claude Opus 5.5 (High)".
        reg = v4_reg()
        ids = (
            "anthropic/claude-opus-5.5",
            "anthropic/claude-fable-5-1[1m]",
            "openai/gpt-6-astra",
        )
        for mid in ids:
            refresh.ensure_model(reg, mid)
        refresh.apply_overrides(reg)
        names = ("Claude Opus 5.5 (High)", "Claude Fable 5.1 (Max)", "GPT-6 Astra")
        rows = []
        for n, name in enumerate(names):
            key, effort = boards.split_effort(name)
            rows.append(
                {
                    "key": key,
                    "score": 1500.0 + n,
                    "ci": None,
                    "effort": effort,
                    "votes": 1,
                }
            )
        got = refresh.match_board(reg, rows)
        self.assertEqual(
            {mid: got.get(mid, {}).get("score") for mid in ids},
            dict(zip(ids, (1500.0, 1501.0, 1502.0))),
        )

    def test_board_min_rows_error_fails_the_feed_and_keeps_data(self):
        reg = v4_reg()
        mid = "anthropic/claude-opus-5.5"
        refresh.ensure_model(reg, mid)
        reg["models"][mid]["boards"]["eq_bench"] = {
            "score": 1500.0,
            "ci": None,
            "effort": None,
            "votes": None,
            "as_of": "2026-11-01",
        }

        def feed(_reg, _cache):
            raise boards.MinRowsError("eq_bench: 3 rows, minimum 24")

        refresh.run_feeds(reg, {"eq_bench": feed}, [], TODAY, "h", {})
        self.assertEqual(reg["sources"]["eq_bench"]["status"], "failed")
        self.assertEqual(reg["models"][mid]["boards"]["eq_bench"]["score"], 1500.0)

    def test_means_use_cached_language_rows(self):
        cache: dict[str, list[dict[str, Any]]] = {
            f"arena_{lang}": [
                {
                    "key": "m",
                    "score": 1000.0 + i,
                    "ci": None,
                    "effort": None,
                    "votes": 1,
                }
                for _ in range(1)
            ]
            for i, lang in enumerate(boards.ARENA_LANGS)
        }
        rows = refresh.lang_mean_rows("arena_lang_mean", cache, min_rows=1)
        self.assertEqual(len(rows), 1)
        with self.assertRaises(refresh.FeedMinRowsError):
            refresh.lang_mean_rows("arena_lang_mean", cache)


class Retired(unittest.TestCase):
    def test_deep_swe_and_aa_api_are_retired_and_values_kept(self):
        reg = v4_reg()
        reg["sources"]["deep_swe"] = {"status": "ok", "as_of": "2026-09-01", "rows": 4}
        reg["sources"]["aa_api"] = {"status": "ok"}
        refresh.mark_retired(reg)
        self.assertEqual(reg["sources"]["deep_swe"]["status"], "retired")
        self.assertEqual(reg["sources"]["deep_swe"]["as_of"], "2026-09-01")
        self.assertEqual(reg["sources"]["aa_api"]["status"], "retired")
        self.assertNotIn("deep_swe", refresh.FEEDS)
        self.assertNotIn("aa_api", refresh.FEEDS)


class Derive(unittest.TestCase):
    def test_band_confidence_and_placement(self):
        reg = v4_reg()
        mid = "z-ai/glm-5.3"
        refresh.ensure_model(reg, mid)
        reg["models"][mid]["variants"]["max"] = {**refresh.variant_stub(), "aai": 31.7}
        refresh.derive_variants(reg)
        v = reg["models"][mid]["variants"]
        self.assertEqual((v["max"]["band"], v["max"]["confidence"]), ("haiku", "high"))
        self.assertEqual(v["max"]["aai_source"], "aa_free")
        # placement-only variant is created, aai stays null, band comes from the override
        self.assertIsNone(v["xhigh"]["aai"])
        self.assertEqual(v["xhigh"]["aai_source"], "placement")
        self.assertEqual(
            (v["xhigh"]["band"], v["xhigh"]["confidence"]), ("haiku", "low")
        )

    def test_measured_beats_placement(self):
        reg = v4_reg()
        mid = "z-ai/glm-5.3"
        refresh.ensure_model(reg, mid)
        reg["models"][mid]["variants"]["xhigh"] = {
            **refresh.variant_stub(),
            "aai": 45.0,
        }
        refresh.derive_variants(reg)
        self.assertEqual(reg["models"][mid]["variants"]["xhigh"]["band"], "sonnet")

    def test_mythos_by_name(self):
        reg = v4_reg()
        mid = "anthropic/claude-fable-5-1[1m]"
        refresh.ensure_model(reg, mid)
        reg["models"][mid]["variants"]["low"] = {**refresh.variant_stub(), "aai": 10.0}
        refresh.derive_variants(reg)
        self.assertEqual(reg["models"][mid]["variants"]["low"]["band"], "mythos")


class EndToEnd(unittest.TestCase):
    def test_refresh_never_writes_policy_or_overrides_and_passes_validate(self):
        reg = v4_reg()
        mid = "anthropic/claude-sonnet-5.5"
        refresh.ensure_model(reg, mid)
        policy, overrides = (
            copy.deepcopy(reg["policy"]),
            copy.deepcopy(reg["overrides"]),
        )
        rows = refresh.parse_aa_free(
            [jread("aa_free_p1.json"), jread("aa_free_p2.json")], min_rows=1
        )
        page = refresh.parse_page(
            read("aa_page_lcr.html"), refresh.PAGE_SPECS["aa_page_lcr"], min_rows=1
        )

        def feed_aa(r, _c):
            return refresh.aa_free_result(r, rows)

        def feed_page(r, _c):
            return refresh.page_result(r, page)

        refresh.run_feeds(
            reg, {"aa_free": feed_aa, "aa_page_lcr": feed_page}, [], TODAY, "h", {}
        )
        refresh.finalize(reg)
        m = reg["models"][mid]
        self.assertEqual(m["variants"]["high"]["aai"], 41.5)
        self.assertEqual(m["variants"]["high"]["band"], "sonnet")
        self.assertAlmostEqual(m["variants"]["max"]["page"]["tb4"], 0.636363636363636)
        self.assertEqual(m["aa_pricing"], {"input": 2, "output": 10})
        self.assertEqual(reg["policy"], policy)
        self.assertEqual(reg["overrides"], overrides)
        self.assertEqual(registry.validate(reg), [])
        self.assertEqual(refresh.hand_owned_errors(reg, policy, overrides), [])

    def test_hand_owned_guard_detects_edits(self):
        reg = v4_reg()
        policy, overrides = (
            copy.deepcopy(reg["policy"]),
            copy.deepcopy(reg["overrides"]),
        )
        reg["policy"]["cost"]["blend"]["input"] = 1.0
        self.assertTrue(refresh.hand_owned_errors(reg, policy, overrides))

    def test_skip_marks_source_skipped(self):
        reg = v4_reg()
        refresh.run_feeds(
            reg,
            {"eq_bench": lambda _r, _c: refresh.FeedResult()},
            ["eq_bench"],
            TODAY,
            "h",
            {},
        )
        self.assertEqual(reg["sources"]["eq_bench"]["status"], "skipped")

    def test_critical_missing_roster_refuses_write(self):
        reg = v4_reg()
        reg["hosts"]["h"] = {"roster": {}}
        self.assertFalse(refresh.critical_ok(reg, "h"))

    def test_write_is_atomic_with_backup(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.json")
            reg = v4_reg()
            refresh.write_registry(reg, p)
            reg["updated_at"] = "2026-11-02T00:00:00Z"
            refresh.write_registry(reg, p)
            self.assertTrue(os.path.exists(p + ".bak"))
            with open(p + ".bak") as f:
                self.assertEqual(json.load(f)["updated_at"], "2026-11-01T00:00:00Z")
            self.assertEqual(registry.load(p)["updated_at"], "2026-11-02T00:00:00Z")


class Retry(unittest.TestCase):
    """fetch retries 429, 5xx, timeouts, and connection errors with backoff."""

    def http_error(
        self, code: int, retry_after: str | None = None
    ) -> urllib.error.HTTPError:
        msg = http.client.HTTPMessage()
        if retry_after is not None:
            msg["Retry-After"] = retry_after
        err = urllib.error.HTTPError("https://x", code, "x", msg, None)
        self.addCleanup(err.close)  # else a ResourceWarning at exit
        return err

    def fetch(
        self,
        outcomes: list[Any],
        deadline: float | None = None,
        jitter: float = 1.0,
    ) -> tuple[Any, list[float], int]:
        calls: list[str] = []

        def once(url, data=None, headers=None, *, redirects=True):
            calls.append(url)
            out = outcomes.pop(0)
            if isinstance(out, BaseException):
                raise out
            return out

        with (
            mock.patch.object(refresh, "_fetch_once", once),
            mock.patch.object(refresh.time, "sleep") as sleep,
            mock.patch.object(refresh.time, "monotonic", return_value=0.0),
            mock.patch.object(refresh.time, "time", return_value=1_000_000.0),
            mock.patch.object(refresh.random, "uniform", return_value=jitter),
        ):
            try:
                got: Any = refresh.fetch("https://x", deadline=deadline)
            except (OSError, http.client.HTTPException) as e:
                got = e
        return got, [c.args[0] for c in sleep.call_args_list], len(calls)

    def test_server_error_then_success(self):
        got, sleeps, n = self.fetch([self.http_error(503), b"ok"])
        self.assertEqual((got, sleeps, n), (b"ok", [2], 2))

    def test_client_error_is_not_retried(self):
        got, sleeps, n = self.fetch([self.http_error(404)])
        self.assertIsInstance(got, urllib.error.HTTPError)
        self.assertEqual((sleeps, n), ([], 1))

    def test_timeouts_exhaust_four_attempts(self):
        got, sleeps, n = self.fetch([TimeoutError("t")] * 4)
        self.assertIsInstance(got, TimeoutError)
        self.assertEqual((sleeps, n), ([2, 4, 8], 4))

    def test_no_backoff_past_the_deadline(self):
        got, sleeps, n = self.fetch([self.http_error(502)] * 4, deadline=3.0)
        self.assertIsInstance(got, urllib.error.HTTPError)
        self.assertEqual((sleeps, n), ([2], 2))

    def test_rate_limit_waits_exactly_retry_after_seconds(self):
        got, sleeps, n = self.fetch([self.http_error(429, "7"), b"ok"])
        self.assertEqual((got, sleeps, n), (b"ok", [7], 2))

    def test_rate_limit_parses_an_http_date_retry_after(self):
        when = email.utils.formatdate(1_000_090, usegmt=True)
        got, sleeps, n = self.fetch([self.http_error(429, when), b"ok"])
        self.assertEqual((got, sleeps, n), (b"ok", [90], 2))

    def test_rate_limit_past_http_date_waits_zero(self):
        when = email.utils.formatdate(999_000, usegmt=True)
        got, sleeps, _ = self.fetch([self.http_error(429, when), b"ok"])
        self.assertEqual((got, sleeps), (b"ok", [0]))

    def test_rate_limit_without_header_backs_off_exponentially(self):
        got, sleeps, n = self.fetch([self.http_error(429)] * 6)
        self.assertIsInstance(got, urllib.error.HTTPError)
        self.assertEqual((sleeps, n), ([5, 10, 20, 40, 80], 6))

    def test_rate_limit_backoff_is_jittered(self):
        _, sleeps, _ = self.fetch([self.http_error(429), b"ok"], jitter=0.5)
        self.assertEqual(sleeps, [2.5])

    def test_garbled_retry_after_falls_back_to_backoff(self):
        got, sleeps, _ = self.fetch([self.http_error(429, "soon"), b"ok"])
        self.assertEqual((got, sleeps), (b"ok", [5]))

    def test_rate_limit_and_server_errors_count_separately(self):
        got, sleeps, n = self.fetch([self.http_error(429), self.http_error(503), b"ok"])
        self.assertEqual((got, sleeps, n), (b"ok", [5, 2], 3))

    def test_retry_after_over_the_cap_raises_without_a_deadline(self):
        got, sleeps, n = self.fetch([self.http_error(429, "121"), b"ok"])
        self.assertIsInstance(got, urllib.error.HTTPError)
        self.assertEqual((sleeps, n), ([], 1))

    def test_retry_after_at_the_cap_is_honored(self):
        got, sleeps, _ = self.fetch([self.http_error(429, "120"), b"ok"])
        self.assertEqual((got, sleeps), (b"ok", [120]))

    def test_rate_limit_never_sleeps_past_the_deadline(self):
        got, sleeps, n = self.fetch([self.http_error(429, "30"), b"ok"], deadline=20.0)
        self.assertIsInstance(got, urllib.error.HTTPError)
        self.assertEqual((sleeps, n), ([], 1))

    def test_jittered_backoff_never_sleeps_past_the_deadline(self):
        got, sleeps, n = self.fetch([self.http_error(429), b"ok"], deadline=4.0)
        self.assertIsInstance(got, urllib.error.HTTPError)
        self.assertEqual((sleeps, n), ([], 1))

    def test_other_client_errors_ignore_retry_after(self):
        got, sleeps, n = self.fetch([self.http_error(403, "5"), b"ok"])
        self.assertIsInstance(got, urllib.error.HTTPError)
        self.assertEqual((sleeps, n), ([], 1))


def _rows_page(off: int, total: int) -> bytes:
    rows = [
        {"row": {"model_name": f"m{i}", "rating": 1000.0, "category": "chinese"}}
        for i in range(off, min(off + 100, total))
    ]
    return json.dumps({"rows": rows, "num_rows_total": total}).encode()


HUB_URL = "https://huggingface.co/api/datasets/lmarena-ai/leaderboard-dataset"


def _hub(sha: str) -> bytes:
    return json.dumps({"id": "lmarena-ai/leaderboard-dataset", "sha": sha}).encode()


class Env(unittest.TestCase):
    """Each test gets its own cache dir and no HF_TOKEN unless it sets one."""

    def setUp(self) -> None:
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.cache = d.name
        env = mock.patch.dict(os.environ, {"XDG_CACHE_HOME": d.name})
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("HF_TOKEN", None)

    def cache_file(self, config: str = "text") -> Path:
        return Path(self.cache) / "agents" / "model-selection" / f"arena-{config}.json"


class ArenaBase(Env):
    def fetch_board(
        self,
        total: int,
        clock: Any = None,
        hub: Any = None,
        board: str = "arena_chinese",
    ) -> tuple[Any, list[str], Any]:
        """Run fetch_board; `hub` is the Hub reply (bytes) or an error to raise."""
        urls: list[str] = []
        hub = OSError("hub down") if hub is None else hub

        def fake(url, data=None, headers=None, *, redirects=True, deadline=None):
            self.seen.append((url, dict(headers or {}), redirects))
            if url == HUB_URL:
                if isinstance(hub, BaseException):
                    raise hub
                return hub
            urls.append(url)
            return _rows_page(int(url.split("offset=")[1].split("&")[0]), total)

        self.seen: list[tuple[str, dict[str, str], bool]] = []
        with (
            mock.patch.object(refresh, "fetch", fake),
            mock.patch.object(refresh.time, "sleep") as sleep,
            mock.patch.object(
                refresh.time, "monotonic", side_effect=clock or (lambda: 0.0)
            ),
        ):
            try:
                got: Any = refresh.fetch_board(board)
            except TimeoutError as e:
                got = e
        return got, urls, sleep


class ArenaPaging(ArenaBase):
    def test_pages_in_order_with_a_gap_between_pages(self):
        pages, urls, sleep = self.fetch_board(250)
        self.assertEqual(len(pages), 3)
        self.assertEqual(
            [u.split("offset=")[1] for u in urls],
            ["0&length=100", "100&length=100", "200&length=100"],
        )
        self.assertEqual(sleep.call_count, 2)
        self.assertTrue(all(c.args[0] >= 1.0 for c in sleep.call_args_list))

    def test_pacing_and_wall_time_constants(self):
        self.assertEqual((refresh.PAGE_GAP, refresh.FEED_WALL), (1.0, 600))

    def test_page_cap_covers_the_text_config(self):
        pages, _, _ = self.fetch_board(11175)
        self.assertEqual(len(pages), 112)

    def test_feed_past_its_wall_time_fails(self):
        ticks = iter([0.0, 0.0, 601.0, 602.0, 603.0])
        got, urls, _ = self.fetch_board(1000, clock=lambda: next(ticks))
        self.assertIsInstance(got, TimeoutError)
        self.assertEqual(len(urls), 1)

    def test_feed_inside_its_wall_time_keeps_paging(self):
        ticks = iter([0.0, 0.0, 301.0, 302.0, 303.0, 304.0])
        got, _, _ = self.fetch_board(250, clock=lambda: next(ticks))
        self.assertEqual(len(got), 3)

    def test_boards_on_one_config_share_one_fetch(self):
        calls: list[str] = []

        def fake_board(board: str) -> list[Any]:
            calls.append(board)
            return [json.loads(_rows_page(0, 1))]

        feeds = refresh.build_feeds()
        with mock.patch.object(refresh, "fetch_board", fake_board):
            for b in ("arena_chinese", "arena_korean", "arena_webdev"):
                with self.assertRaises(boards.MinRowsError):
                    feeds[b](v4_reg(), {})
        self.assertEqual(calls, ["arena_chinese", "arena_webdev"])

    def test_a_failed_config_fetch_is_not_repeated(self):
        calls: list[str] = []

        def fake_board(board: str) -> list[Any]:
            calls.append(board)
            raise TimeoutError("arena: feed ran past 600 s")

        feeds = refresh.build_feeds()
        with mock.patch.object(refresh, "fetch_board", fake_board):
            for b in ("arena_chinese", "arena_korean"):
                with self.assertRaises(TimeoutError):
                    feeds[b](v4_reg(), {})
        self.assertEqual(calls, ["arena_chinese"])


class ArenaRevision(ArenaBase):
    """Page a config only when its Hub revision changed."""

    SHA = "0123456789abcdef"

    def test_first_run_pages_and_writes_the_cache(self):
        pages, urls, _ = self.fetch_board(250, hub=_hub(self.SHA))
        self.assertEqual(len(urls), 3)
        stored = json.loads(self.cache_file().read_text())
        self.assertEqual(stored, {"sha": self.SHA, "pages": pages})
        self.assertEqual(list(self.cache_file().parent.glob("*.tmp")), [])

    def test_unchanged_revision_pages_nothing_and_logs_it(self):
        first, _, _ = self.fetch_board(250, hub=_hub(self.SHA))
        with mock.patch.object(refresh, "log") as lg:
            again, urls, sleep = self.fetch_board(250, hub=_hub(self.SHA))
        self.assertEqual((again, urls, sleep.call_count), (first, [], 0))
        lines = [c.args[0] for c in lg.call_args_list]
        self.assertEqual(len(lines), 1)
        self.assertIn("0123456", lines[0])
        self.assertNotIn(self.SHA, lines[0])
        self.assertIn("unchanged", lines[0])

    def test_changed_revision_pages_again_and_rewrites_the_cache(self):
        self.fetch_board(250, hub=_hub(self.SHA))
        _, urls, _ = self.fetch_board(250, hub=_hub("fedcba9876543210"))
        self.assertEqual(len(urls), 3)
        stored = json.loads(self.cache_file().read_text())
        self.assertEqual(stored["sha"], "fedcba9876543210")

    def test_each_config_has_its_own_cache_file(self):
        self.fetch_board(10, hub=_hub(self.SHA), board="arena_webdev")
        self.assertTrue(self.cache_file("webdev").exists())
        self.assertFalse(self.cache_file("text").exists())

    def test_failed_hub_check_pages_and_logs_the_reason(self):
        with mock.patch.object(refresh, "log") as lg:
            pages, urls, _ = self.fetch_board(250, hub=OSError("hub down"))
        self.assertEqual((len(pages), len(urls)), (3, 3))
        self.assertTrue(any("hub down" in c.args[0] for c in lg.call_args_list))
        self.assertFalse(self.cache_file().exists())

    def test_hub_reply_without_a_sha_counts_as_a_failed_check(self):
        with mock.patch.object(refresh, "log") as lg:
            _, urls, _ = self.fetch_board(150, hub=b'{"id": "x"}')
        self.assertEqual(len(urls), 2)
        self.assertTrue(lg.called)

    def test_hub_reply_that_is_not_json_counts_as_a_failed_check(self):
        _, urls, _ = self.fetch_board(150, hub=b"<html>")
        self.assertEqual(len(urls), 2)

    def test_missing_or_corrupt_cache_pages_as_before(self):
        for junk in ("{not json", json.dumps({"sha": self.SHA}), "[]"):
            self.cache_file().parent.mkdir(parents=True, exist_ok=True)
            self.cache_file().write_text(junk)
            _, urls, _ = self.fetch_board(150, hub=_hub(self.SHA))
            self.assertEqual(len(urls), 2, junk)
            self.assertEqual(json.loads(self.cache_file().read_text())["sha"], self.SHA)

    def test_cache_is_not_written_after_a_failed_paging(self):
        got, _, _ = self.fetch_board(
            1000,
            hub=_hub(self.SHA),
            clock=iter([0.0, 0.0, 601.0] + [602.0] * 9).__next__,
        )
        self.assertIsInstance(got, TimeoutError)
        self.assertFalse(self.cache_file().exists())

    def test_cache_write_is_a_rename_of_a_temp_file(self):
        real = os.replace
        seen: list[bool] = []

        def spy(src, dst):
            seen.append(os.path.exists(src) and not os.path.exists(dst))
            real(src, dst)

        with mock.patch.object(os, "replace", spy):
            self.fetch_board(10, hub=_hub(self.SHA))
        self.assertEqual(seen, [True])

    def test_unwritable_cache_does_not_fail_the_feed(self):
        with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": "/proc/nope"}):
            pages, _, _ = self.fetch_board(10, hub=_hub(self.SHA))
        self.assertEqual(len(pages), 1)

    def test_cache_dir_reads_the_environment_at_call_time(self):
        with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": "/x/y"}):
            self.assertEqual(refresh.cache_dir(), "/x/y/agents/model-selection")
        with mock.patch.dict(os.environ):
            os.environ.pop("XDG_CACHE_HOME")
            self.assertEqual(
                refresh.cache_dir(),
                os.path.expanduser("~/.cache/agents/model-selection"),
            )

    def test_cached_pages_still_make_the_feed_ok(self):
        self.fetch_board(250, hub=_hub(self.SHA))
        with (
            mock.patch.object(refresh, "fetch", side_effect=_no_pages),
            mock.patch.object(refresh.time, "sleep"),
        ):
            pages = refresh.fetch_board("arena_chinese")
        self.assertEqual(len(refresh.parse_board("arena_chinese", pages)), 250)


def _no_pages(url, *a, **k):
    if url == HUB_URL:
        return _hub(ArenaRevision.SHA)
    raise AssertionError(f"paged {url}")


class HfToken(ArenaBase):
    """HF_TOKEN goes only to Hugging Face hosts, never follows a redirect."""

    def test_header_goes_to_both_hf_hosts_without_redirects(self):
        with mock.patch.dict(os.environ, {"HF_TOKEN": " hf_FAKE\n"}):
            self.fetch_board(10, hub=_hub("abc1234"))
        hosts = {u.split("/")[2]: (h, r) for u, h, r in self.seen}
        self.assertEqual(
            set(hosts), {"huggingface.co", "datasets-server.huggingface.co"}
        )
        for headers, redirects in hosts.values():
            self.assertEqual(headers["Authorization"], "Bearer hf_FAKE")
            self.assertFalse(redirects)

    def test_header_is_absent_for_a_non_hf_host(self):
        for url in (
            "https://example.com/x",
            "https://evilhuggingface.co/x",
            "https://huggingface.co.evil.com/x",
        ):
            self.assertNotIn("Authorization", refresh.hf_headers(url, "hf_FAKE"), url)

    def test_header_is_present_for_hf_hosts(self):
        for url in (
            "https://huggingface.co/api/x",
            "https://datasets-server.huggingface.co/rows",
        ):
            self.assertEqual(
                refresh.hf_headers(url, "hf_FAKE")["Authorization"], "Bearer hf_FAKE"
            )

    def test_unset_token_sends_no_header_and_allows_redirects(self):
        self.fetch_board(10, hub=_hub("abc1234"))
        for _, headers, redirects in self.seen:
            self.assertNotIn("Authorization", headers)
            self.assertTrue(redirects)

    def test_blank_token_sends_no_header(self):
        with mock.patch.dict(os.environ, {"HF_TOKEN": "  \n"}):
            self.fetch_board(10, hub=_hub("abc1234"))
        self.assertTrue(all("Authorization" not in h for _, h, _ in self.seen))

    def test_token_with_control_characters_is_not_sent_and_not_logged(self):
        with (
            mock.patch.dict(os.environ, {"HF_TOKEN": "hf_FAKE\nSECRET"}),
            mock.patch.object(refresh, "log") as lg,
        ):
            pages, _, _ = self.fetch_board(10, hub=_hub("abc1234"))
        self.assertEqual(len(pages), 1)
        self.assertTrue(all("Authorization" not in h for _, h, _ in self.seen))
        logged = " ".join(c.args[0] for c in lg.call_args_list)
        self.assertIn("HF_TOKEN", logged)
        self.assertNotIn("hf_FAKE", logged)
        self.assertNotIn("SECRET", logged)

    def test_redact_scrubs_the_token_in_every_form(self):
        with mock.patch.dict(os.environ, {"HF_TOKEN": "hf_FAKE\n"}):
            text = "bad header 'hf_FAKE' b'hf_FAKE\\n' hf_FAKE\n"
            out = refresh.redact(text)
        self.assertNotIn("hf_FAKE", out)
        self.assertIn("***", out)

    def test_redact_still_scrubs_the_aa_key(self):
        with mock.patch.dict(
            os.environ, {"AA_API_KEY": "aa_FAKE", "HF_TOKEN": "hf_FAKE"}
        ):
            out = refresh.redact("aa_FAKE and hf_FAKE")
        self.assertEqual(out, "*** and ***")


class Repair(unittest.TestCase):
    def test_key_with_newline_is_refused_without_echo(self):
        with mock.patch.dict(os.environ, {"AA_API_KEY": "FAKE-SECRET\nKEY-123"}):
            res = refresh.feed_aa_free(v4_reg(), {})
        self.assertIsNotNone(res.error)
        self.assertNotIn("FAKE-SECRET", res.error or "")

    def test_trailing_newline_key_is_stripped(self):
        seen: dict[str, str] = {}

        def fake_fetch(url, data=None, headers=None, *, redirects=True):
            seen.update(headers or {})
            return b'{"data": [], "pagination": {"has_more": false}}'

        with (
            mock.patch.dict(os.environ, {"AA_API_KEY": "FAKE-KEY\n"}),
            mock.patch.object(refresh, "fetch", fake_fetch),
        ):
            try:
                refresh.feed_aa_free(v4_reg(), {})
            except (LookupError, ValueError):
                pass
        self.assertEqual(seen.get("x-api-key"), "FAKE-KEY")

    def test_key_is_redacted_from_feed_error(self):
        def feed(_reg, _cache):
            raise ValueError("Invalid header value b'FAKE-SECRET-KEY-123\\n'")

        reg = v4_reg()
        with mock.patch.dict(os.environ, {"AA_API_KEY": "FAKE-SECRET-KEY-123\n"}):
            refresh.run_feeds(reg, {"aa_free": feed}, [], TODAY, "h", {})
        err = reg["sources"]["aa_free"]["error"]
        self.assertNotIn("FAKE-SECRET-KEY-123", err)
        self.assertIn("***", err)

    def test_incomplete_read_is_a_feed_failure(self):
        def feed(_reg, _cache):
            raise http.client.IncompleteRead(b"x")

        reg = v4_reg()
        refresh.run_feeds(reg, {"openrouter": feed}, [], TODAY, "h", {})
        self.assertEqual(reg["sources"]["openrouter"]["status"], "failed")

    def test_write_never_leaves_path_missing_and_fsyncs(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.json")
            reg = v4_reg()
            refresh.write_registry(reg, p)
            seen: list[bool] = []
            real = os.replace

            def spy(a, b):
                seen.append(os.path.exists(p))
                real(a, b)

            with (
                mock.patch.object(os, "replace", spy),
                mock.patch.object(os, "fsync") as fs,
            ):
                refresh.write_registry(reg, p)
            self.assertEqual(seen, [True])
            fs.assert_called_once()
            self.assertTrue(os.path.exists(p + ".bak"))
            self.assertFalse(os.path.exists(p + ".tmp"))

    def _pi(self, enabled, n_store):
        with tempfile.TemporaryDirectory() as d:
            sp, st = os.path.join(d, "s.json"), os.path.join(d, "m.json")
            models = [{"id": f"v/m{i}", "reasoning": False} for i in range(n_store)]
            with open(sp, "w") as f:
                json.dump(
                    {"enabledModels": [f"openrouter/v/m{i}" for i in range(enabled)]}, f
                )
            with open(st, "w") as f:
                json.dump({"openrouter": {"models": models}}, f)
            with (
                mock.patch.object(refresh, "PI_SETTINGS", sp),
                mock.patch.object(refresh, "PI_STORE", st),
                mock.patch.object(refresh, "cli_version", lambda _n: "1"),
            ):
                reg = v4_reg()
                out = refresh.refresh_pi(reg, "h", TODAY)
                return out, reg["sources"]["pi_roster"]["status"]

    def test_pi_roster_below_min_rows_fails(self):
        (ok, entries, _), status = self._pi(2, 50)
        self.assertEqual((ok, entries, status), (True, None, "failed"))

    def test_pi_store_below_min_rows_fails(self):
        (_, entries, _), status = self._pi(6, 4)
        self.assertEqual((entries, status), (None, "failed"))

    def test_pi_roster_at_min_rows_ok(self):
        (_, entries, _), status = self._pi(6, 12)
        self.assertEqual(status, "ok")
        self.assertIsNotNone(entries)


if __name__ == "__main__":
    unittest.main()
