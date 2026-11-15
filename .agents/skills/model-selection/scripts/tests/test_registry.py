#!/usr/bin/env python3
"""Behaviour tests for registry.py and the staged v4 registry.  stdlib, offline."""

import copy
import importlib.util
import os
import unittest
from pathlib import Path
from typing import Any

SCRIPTS = Path(__file__).resolve().parent.parent
# Read-only: the live registry is the file the staged code reads.
REGISTRY_FILE = Path(
    os.environ.get("MODEL_SELECTION_REGISTRY")
    or Path.home() / ".agents" / "model-benchmarks.json"
)

spec = importlib.util.spec_from_file_location("registry", SCRIPTS / "registry.py")
assert spec is not None and spec.loader is not None
registry: Any = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)

# CONTRACT section 3, verbatim.
CONTRACT_POLICY: dict[str, Any] = {
    "bands": {
        "order": ["bulk", "haiku", "sonnet", "opus", "mythos"],
        "index": "aai_v5",
        "reference_effort": "high",
        "floors": {"bulk": 20.9, "haiku": 28.4, "sonnet": 39.4, "opus": 49.2},
        "anchors": {
            "haiku": {
                "model": "anthropic/claude-haiku-5.5",
                "effort": "high",
                "aai": 29.9,
            },
            "sonnet": {
                "model": "anthropic/claude-sonnet-5.5",
                "effort": "high",
                "aai": 41.5,
            },
            "opus": {
                "model": "anthropic/claude-opus-5.5",
                "effort": "high",
                "aai": 51.8,
            },
            "bulk": {"rule": "0.70 x haiku anchor"},
        },
        "mythos": [
            "anthropic/claude-fable-5-1[1m]",
            "openai/gpt-6-astra",
            "openai/gpt-6-astra-pro",
        ],
    },
    "tags": {
        "design": {"kind": "skill", "board": "arena_webdev", "margin": "ci"},
        "3d": {"kind": "skill", "board": "aa_3d", "margin": "ci"},
        "math": {"kind": "skill", "board": "matharena", "margin": "ci"},
        "writing": {"kind": "skill", "board": "arena_creative_writing", "margin": "ci"},
        "eq": {"kind": "skill", "board": "eq_bench", "margin": 10},
        "long-horizon": {"kind": "skill", "board": "tb4", "margin": 0.10},
        "cyber": {
            "kind": "domain",
            "board": "aa_cyber",
            "margin": 2,
            "refusal_reroute": True,
        },
        "medical": {
            "kind": "domain",
            "board": "health_med",
            "margin": 2,
            "tiebreak": "healthbench",
            "refusal_reroute": True,
        },
        "business": {"kind": "domain", "board": "business", "margin": 2},
        "multilingual": {
            "kind": "language",
            "board": "arena_lang_mean",
            "margin": 10,
        },
        "chinese": {"kind": "language", "board": "arena_chinese", "margin": "ci"},
        "european": {
            "kind": "language",
            "board": "arena_european_mean",
            "margin": 10,
        },
        "japanese": {"kind": "language", "board": "arena_japanese", "margin": "ci"},
    },
    "roles": {
        "executive": {"band": "opus", "effort": "xhigh", "rank_on": "long-horizon"},
        "coordinator": {"band": "sonnet", "effort": "high", "rank_on": "long-horizon"},
        "worker": {"band": None, "effort": "medium"},
    },
    "mix": {"haiku_or_below": 0.16, "sonnet": 0.64, "opus_or_above": 0.20},
    "harnesses": {
        "claude-code": {
            "runs": ["anthropic"],
            "tool": "Agent",
            "efforts": ["low", "medium", "high", "xhigh", "max"],
        },
        "pi": {
            "runs": ["openrouter"],
            "command": (
                "pi --model {model_ref} --thinking {effort} --no-session "
                '-p "$(cat {payload})" < /dev/null'
            ),
        },
    },
    "profiles": {
        "claude-code": {
            "primary": "claude-code",
            "harnesses": {
                "claude-code": {"billing": "subscription"},
                "pi": {"billing": "metered", "roster": "pi-zdr"},
            },
        },
        "claude-code-bedrock": {
            "primary": "claude-code",
            "harnesses": {
                "claude-code": {"billing": "metered", "price_source": "bedrock"}
            },
        },
        "pi-zdr": {
            "primary": "pi",
            "harnesses": {"pi": {"billing": "metered", "roster": "pi-zdr"}},
            "empty_band": "degrade",
        },
        "pi-permissive": {
            "primary": "pi",
            "placeholder": True,
            "harnesses": {"pi": {"billing": "metered", "roster": "pi-enabled"}},
        },
    },
    "cost": {"blend": {"input": 0.75, "output": 0.25}},
    "stale_days": 14,
    "age_out_days": 90,
    "models_store_stale_days": 7,
}

# enabledModels (OpenRouter, minus auto and :free) intersected with the
# models-store ids, recorded at migration on 2026-11-09.
PI_ZDR_AT_MIGRATION = {
    "deepseek/deepseek-v4.1-flash",
    "google/gemma-4-26b-a4b-it",
    "google/gemma-4-31b-it",
    "minimax/minimax-m3",
    "moonshotai/kimi-k3",
    "nvidia/nemotron-3.5-lightning",
    "openai/gpt-5.6-sol",
    "qwen/qwen3.6-35b-a3b",
    "qwen/qwen3.8-27b",
    "z-ai/glm-5.3",
    "z-ai/glm-5.3-flash",
}

PLACEMENTS = {
    ("openai/gpt-5.6-sol", "high"): (33.3, "low"),
    ("openai/gpt-5.6-sol", "xhigh"): (35.4, "low"),
    ("moonshotai/kimi-k3", "max"): (30.4, "medium"),
    ("qwen/qwen3.8-2.4t-a95b", "single"): (25.5, "medium"),
    ("google/gemini-3.7-flash", "high"): (26.1, "low"),
    ("deepseek/deepseek-v4.1-flash", "max"): (28.2, "low"),
}


def minimal_registry() -> dict[str, Any]:
    return {
        "schema_version": 4,
        "updated_at": "2026-11-09T00:00:00Z",
        "notes": [],
        "policy": copy.deepcopy(CONTRACT_POLICY),
        "overrides": {},
        "models": {
            "z-ai/glm-5.3": {
                "provider": "z-ai",
                "pricing": {"input": 1.0, "output": 2.0, "source": "openrouter"},
                "variants": {"max": {"aai": 31.7, "band": "haiku"}},
            }
        },
        "hosts": {},
        "sources": {},
    }


class BandOf(unittest.TestCase):
    def test_mythos_matches_other_spellings_of_a_listed_id(self) -> None:
        for alias in (
            "anthropic/claude-fable-5.1",
            "anthropic/claude-fable-5-1",
            "openai/gpt-6-astra:free",
            "OpenAI/GPT-6-Astra",
        ):
            with self.subTest(alias=alias):
                self.assertEqual(
                    registry.band_of(30.0, alias, CONTRACT_POLICY), "mythos"
                )

    def test_mythos_alias_rule_does_not_swallow_neighbours(self) -> None:
        got = registry.band_of(30.0, "openai/gpt-6-astra-mini", CONTRACT_POLICY)
        self.assertEqual(got, "haiku")

    def test_mythos_by_name_whatever_the_aai(self) -> None:
        got = registry.band_of(10.0, "openai/gpt-6-astra", CONTRACT_POLICY)
        self.assertEqual(got, "mythos")

    def test_haiku_floor(self) -> None:
        self.assertEqual(registry.band_of(28.4, "x/y", CONTRACT_POLICY), "haiku")

    def test_just_below_haiku_is_bulk(self) -> None:
        self.assertEqual(registry.band_of(28.3, "x/y", CONTRACT_POLICY), "bulk")

    def test_below_bulk_is_unbanded(self) -> None:
        self.assertIsNone(registry.band_of(20.8, "x/y", CONTRACT_POLICY))

    def test_no_aai_is_unbanded(self) -> None:
        self.assertIsNone(registry.band_of(None, "x/y", CONTRACT_POLICY))


class EffectiveAai(unittest.TestCase):
    def reg(self, measured: float | None) -> dict[str, Any]:
        reg = minimal_registry()
        reg["models"]["m/x"] = {"variants": {"high": {"aai": measured}}}
        reg["overrides"]["m/x"] = {
            "placements": {"high": {"aai": 33.3, "confidence": "low"}}
        }
        return reg

    def test_measured_wins_over_placement(self) -> None:
        aai, conf, _ = registry.effective_aai(self.reg(40.0), "m/x", "high")
        self.assertEqual((aai, conf), (40.0, "high"))

    def test_placement_used_when_unmeasured(self) -> None:
        aai, conf, src = registry.effective_aai(self.reg(None), "m/x", "high")
        self.assertEqual((aai, conf, src), (33.3, "low", "placement"))


class Cost(unittest.TestCase):
    def test_repriced_cost_ratio_of_blends(self) -> None:
        # blend(channel) = 0.75*2 + 0.25*4 = 2.5; blend(aa) = 0.75*1 + 0.25*2 = 1.25
        got = registry.repriced_cost(
            100.0,
            {"input": 2.0, "output": 4.0},
            {"input": 1.0, "output": 2.0},
            CONTRACT_POLICY,
        )
        self.assertAlmostEqual(got, 200.0)

    def test_repriced_cost_none_without_index_cost(self) -> None:
        got = registry.repriced_cost(
            None, {"input": 1, "output": 1}, {}, CONTRACT_POLICY
        )
        self.assertIsNone(got)

    def test_vendor_of_prefix_then_override(self) -> None:
        reg = minimal_registry()
        self.assertEqual(registry.vendor_of(reg, "z-ai/glm-5.3"), "z-ai")
        reg["overrides"]["z-ai/glm-5.3"] = {"vendor": "zhipu"}
        self.assertEqual(registry.vendor_of(reg, "z-ai/glm-5.3"), "zhipu")


class Validate(unittest.TestCase):
    def test_minimal_registry_is_clean(self) -> None:
        self.assertEqual(registry.validate(minimal_registry()), [])

    def test_wrong_schema_version(self) -> None:
        reg = minimal_registry()
        reg["schema_version"] = 3
        self.assertTrue(registry.validate(reg))

    def test_missing_policy(self) -> None:
        reg = minimal_registry()
        del reg["policy"]
        self.assertTrue(any("policy" in e for e in registry.validate(reg)))

    def test_negative_price(self) -> None:
        reg = minimal_registry()
        reg["models"]["z-ai/glm-5.3"]["pricing"]["input"] = -1.0
        self.assertTrue(
            any("price" in e or "pricing" in e for e in registry.validate(reg))
        )

    def test_effort_outside_efforts(self) -> None:
        reg = minimal_registry()
        reg["models"]["z-ai/glm-5.3"]["variants"]["ultra"] = {"aai": 1.0}
        self.assertTrue(any("ultra" in e for e in registry.validate(reg)))

    def test_unknown_band_name(self) -> None:
        reg = minimal_registry()
        reg["models"]["z-ai/glm-5.3"]["variants"]["max"]["band"] = "platinum"
        self.assertTrue(any("platinum" in e for e in registry.validate(reg)))

    def _variant(self) -> dict[str, Any]:
        return minimal_registry()["models"]["z-ai/glm-5.3"]["variants"]["max"]

    def _with(self, **kw: Any) -> list[str]:
        reg = minimal_registry()
        reg["models"]["z-ai/glm-5.3"]["variants"]["max"].update(kw)
        return registry.validate(reg)

    def test_unknown_page_key_rejected(self) -> None:
        self.assertTrue(any("bogus" in e for e in self._with(page={"bogus": 1})))

    def test_omniscience_page_keys_allowed(self) -> None:
        self.assertEqual(
            self._with(page={"omniscience": 1.0, "factuality": 0.5, "tb4": None}), []
        )

    def test_unknown_domain_key_rejected(self) -> None:
        self.assertTrue(any("bogus" in e for e in self._with(domains={"bogus": 1})))

    def test_unknown_board_entry_key_rejected(self) -> None:
        reg = minimal_registry()
        reg["models"]["z-ai/glm-5.3"]["boards"] = {"eq_bench": {"score": 1, "x": 2}}
        self.assertTrue(any("x" in e for e in registry.validate(reg)))


@unittest.skipUnless(REGISTRY_FILE.exists(), "registry not found")
class StagedRegistry(unittest.TestCase):
    reg: dict[str, Any]

    @classmethod
    def setUpClass(cls) -> None:
        cls.reg = registry.load(str(REGISTRY_FILE))

    def band(self, model: str, effort: str) -> str | None:
        aai, _, _ = registry.effective_aai(self.reg, model, effort)
        return registry.band_of(aai, model, self.reg["policy"])

    def test_passes_validate(self) -> None:
        self.assertEqual(registry.validate(self.reg), [])

    def test_ci_less_tags_have_numeric_margin(self) -> None:
        tags = self.reg["policy"]["tags"]
        for t in ("multilingual", "european"):
            self.assertIsInstance(tags[t]["margin"], int)

    def test_profiles_name_primary(self) -> None:
        want = {
            "claude-code": "claude-code",
            "claude-code-bedrock": "claude-code",
            "pi-zdr": "pi",
            "pi-permissive": "pi",
        }
        for name, prim in want.items():
            self.assertEqual(self.reg["policy"]["profiles"][name]["primary"], prim)

    def test_pi_command_is_unquoted(self) -> None:
        cmd = self.reg["policy"]["harnesses"]["pi"]["command"]
        self.assertIn("--model {model_ref} ", cmd)

    def test_no_dead_v3_match_keys(self) -> None:
        for mid, m in self.reg["models"].items():
            for k in ("eqbench", "designarena", "deepswe"):
                self.assertNotIn(k, m["match"], mid)
        m = self.reg["models"]["anthropic/claude-haiku-4.5"]["match"]
        self.assertIn("claude-haiku-4-5", m["board"])

    def test_known_bands(self) -> None:
        cases = [
            ("anthropic/claude-haiku-5.5", "high", "haiku"),
            ("anthropic/claude-sonnet-5.5", "medium", "haiku"),
            ("anthropic/claude-opus-5.5", "high", "opus"),
            ("z-ai/glm-5.3", "max", "haiku"),
            ("z-ai/glm-5.3-flash", "single", "bulk"),
        ]
        for model, effort, want in cases:
            with self.subTest(model=model, effort=effort):
                self.assertEqual(self.band(model, effort), want)

    def test_stored_band_matches_derived(self) -> None:
        for mid, m in self.reg["models"].items():
            for eff, v in m["variants"].items():
                with self.subTest(model=mid, effort=eff):
                    self.assertEqual(v["band"], self.band(mid, eff))

    def test_mythos_models_exist(self) -> None:
        for mid in self.reg["policy"]["bands"]["mythos"]:
            self.assertIn(mid, self.reg["models"])

    def test_pi_zdr_roster_at_migration(self) -> None:
        roster = self.reg["hosts"]["lama-pc-01"]["roster"]
        got = {k for k, v in roster.items() if "pi-zdr" in v.get("rosters", [])}
        self.assertEqual(got, PI_ZDR_AT_MIGRATION)

    def test_placements_present_with_confidence(self) -> None:
        for (model, effort), (aai, conf) in PLACEMENTS.items():
            with self.subTest(model=model, effort=effort):
                p = self.reg["overrides"][model]["placements"][effort]
                self.assertEqual((p["aai"], p["confidence"]), (aai, conf))
                self.assertEqual(p["source"], "findings-3 1.2 crosswalk")
                self.assertEqual(p["date"], "2026-11-09")

    def test_sol_max_not_placed_and_noted(self) -> None:
        o = self.reg["overrides"]["openai/gpt-5.6-sol"]
        self.assertNotIn("max", o["placements"])
        self.assertIn("max", o["notes"])

    def test_deepseek_pi_thinking(self) -> None:
        o = self.reg["overrides"]["deepseek/deepseek-v4.1-flash"]
        self.assertEqual(o["pi_thinking"], {"max": "high"})

    def test_policy_equals_contract(self) -> None:
        self.assertEqual(self.reg["policy"], CONTRACT_POLICY)


if __name__ == "__main__":
    unittest.main()
