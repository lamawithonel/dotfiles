#!/usr/bin/env python3
"""Tests for score.py v2: band picks, tags, degrades, effort, and profiles.

Every test builds a small synthetic v4 registry in memory, writes it to a
temporary file, and calls `score.main` with an explicit environment.
"""

import contextlib
import copy
import io
import json
import os
import shlex
import sys
import tempfile
import unittest
from dataclasses import dataclass
from typing import Any, ClassVar

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import score

type Reg = dict[str, Any]

HAIKU = "anthropic/claude-haiku-5.5"
SONNET = "anthropic/claude-sonnet-5.5"
OPUS = "anthropic/claude-opus-5.5"
FABLE = "anthropic/claude-fable-5-1[1m]"
FABLE2 = "anthropic/claude-fable-5-2[1m]"
GLM = "z-ai/glm-5.3"
DSEEK = "deepseek/ds-flash"
GPTX = "openai/gpt-x"
QWEN = "qwen/q-big"
LEVELS = ["off", "low", "high", "max"]
PRICE = {"input": 0.84, "output": 2.64}
CLAUDE_PRICE = {"input": 1.0, "output": 5.0}

POLICY: Reg = {
    "bands": {
        "order": ["bulk", "haiku", "sonnet", "opus", "mythos"],
        "index": "aai_v5",
        "reference_effort": "high",
        "floors": {"bulk": 20.9, "haiku": 28.4, "sonnet": 39.4, "opus": 49.2},
        "mythos": [FABLE, "openai/gpt-6-astra"],
    },
    "tags": {
        "design": {
            "kind": "skill",
            "board": "arena_webdev",
            "margin": "ci",
        },
        "eq": {"kind": "skill", "board": "eq_bench", "margin": 10},
        "writing": {"kind": "skill", "board": "arena_writing", "margin": "ci"},
        "long-horizon": {"kind": "skill", "board": "tb4", "margin": 0.10},
        "cyber": {
            "kind": "domain",
            "board": "aa_cyber",
            "margin": 2,
            "refusal_reroute": True,
        },
        "chinese": {"kind": "language", "board": "arena_chinese", "margin": "ci"},
        "tied": {
            "kind": "skill",
            "board": "eq_bench",
            "margin": 100,
            "tiebreak": "tb4",
        },
    },
    "roles": {
        "orchestrator": {"band": "opus", "effort": "xhigh", "rank_on": "long-horizon"},
        "coordinator": {"band": "sonnet", "effort": "high", "rank_on": "long-horizon"},
        "worker": {"band": None, "effort": "medium"},
    },
    "harnesses": {
        "claude-code": {"runs": ["anthropic"], "tool": "Agent"},
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
            "placeholder": True,
            "primary": "pi",
            "harnesses": {"pi": {"billing": "metered", "roster": "pi-enabled"}},
        },
    },
    "cost": {"blend": {"input": 0.75, "output": 0.25}},
    "stale_days": 14,
    "age_out_days": 90,
    "models_store_stale_days": 7,
}


def _variant(aai: float | None, cost: float | None) -> Reg:
    return {"aai": aai, "index_cost_usd": cost}


def _model(variants: Reg, price: Reg, boards: Reg | None = None) -> Reg:
    return {
        "variants": variants,
        "pricing": dict(price),
        "aa_pricing": dict(price),
        "boards": boards or {},
    }


def _board(score_: float, ci: float | None = None) -> Reg:
    return {"score": score_, "ci": ci}


def _claude_entry(param: str) -> Reg:
    return {
        "harness": "claude-code",
        "enabled": True,
        "model_ref": None,
        "model_param": param,
        "rosters": [],
    }


def _pi_entry(ref: str, rosters: list[str]) -> Reg:
    return {
        "harness": "pi",
        "enabled": True,
        "model_ref": f"openrouter/{ref}",
        "model_param": None,
        "rosters": rosters,
        "pi_levels": list(LEVELS),
        "price": dict(PRICE),
    }


def make_registry() -> Reg:
    """A compact v4 registry covering every band and both harnesses."""
    models = {
        HAIKU: _model(
            {
                "high": _variant(29.9, 100),
                "medium": _variant(27.0, 40),
                "low": _variant(25.0, 60),
            },
            CLAUDE_PRICE,
            {"arena_webdev": _board(1500, 5), "eq_bench": _board(70)},
        ),
        SONNET: _model(
            {"high": _variant(41.5, 300), "medium": _variant(40.0, 200)},
            CLAUDE_PRICE,
            {"aa_cyber": _board(80)},
        ),
        OPUS: _model(
            {"high": _variant(51.8, 900)},
            CLAUDE_PRICE,
            {"tb4": _board(0.6)},
        ),
        FABLE: _model({"high": _variant(60.0, 2000)}, CLAUDE_PRICE),
        GLM: _model(
            {
                "max": _variant(31.7, 2097),
                "high": _variant(29.0, 1500),
                "low": _variant(22.0, 400),
                "off": _variant(15.0, None),
            },
            PRICE,
            {
                "arena_webdev": _board(1560, 5),
                "eq_bench": _board(75),
                "arena_chinese": _board(1500, 5),
            },
        ),
        DSEEK: _model({"max": _variant(30.5, 500), "high": _variant(30.0, 700)}, PRICE),
        GPTX: _model(
            {"high": _variant(42.0, 500)},
            PRICE,
            {"aa_cyber": _board(79)},
        ),
    }
    roster = {
        HAIKU: _claude_entry("haiku"),
        SONNET: _claude_entry("sonnet"),
        OPUS: _claude_entry("opus"),
        FABLE: _claude_entry("fable"),
        GLM: _pi_entry(GLM, ["pi-zdr", "pi-enabled"]),
        DSEEK: _pi_entry(DSEEK, ["pi-enabled"]),
        GPTX: _pi_entry(GPTX, ["pi-zdr", "pi-enabled"]),
    }
    hosts = {
        "h1": {
            "harnesses": {"claude-code": {"healthy": True}, "pi": {"healthy": True}},
            "herdr": "env",
            "default_profile": "claude-code",
            "bedrock_aliases": {},
            "roster": roster,
            "pi_models_store": {"checked_at": "2026-11-09T15:41:48Z", "count": 18},
        },
        "*": {
            "harnesses": {"claude-code": {"healthy": True}},
            "herdr": "env",
            "default_profile": "claude-code",
            "bedrock_aliases": {},
            "roster": {
                k: copy.deepcopy(v) for k, v in roster.items() if k.startswith("anth")
            },
        },
    }
    return {
        "schema_version": 4,
        "updated_at": "2026-11-09",
        "policy": copy.deepcopy(POLICY),
        "overrides": {DSEEK: {"pi_thinking": {"max": "high"}}},
        "models": models,
        "hosts": hosts,
        "sources": {},
    }


@dataclass(frozen=True)
class Result:
    code: int
    data: Any
    out: str
    err: str


class ScoreCase(unittest.TestCase):
    def setUp(self) -> None:
        self.reg = make_registry()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = os.path.join(tmp.name, "reg.json")

    def call(
        self, *args: str, env: dict[str, str] | None = None, host: str = "h1"
    ) -> Result:
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.reg, f)
        argv = [
            "--registry",
            self.path,
            "--host",
            host,
            "--today",
            "2026-11-09",
            *args,
        ]
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = score.main(argv, env or {})
        text = out.getvalue()
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            data = None
        return Result(code, data, text, err.getvalue())

    def pick(self, *args: str, env: dict[str, str] | None = None) -> Result:
        return self.call("--pick", *args, env=env)

    def drop_roster(self, *ids: str, host: str = "h1") -> None:
        for model_id in ids:
            del self.reg["hosts"][host]["roster"][model_id]

    def set_cost(self, model_id: str, effort: str, cost: float) -> None:
        self.reg["models"][model_id]["variants"][effort]["index_cost_usd"] = cost

    def allow_reroute(self) -> None:
        """Price Haiku so GLM stays inside the 1.5x tag cost ceiling."""
        self.set_cost(HAIKU, "high", 1100)

    def set_board(self, model_id: str, board: str, value: Reg | None) -> None:
        boards = self.reg["models"][model_id]["boards"]
        if value is None:
            boards.pop(board, None)
        else:
            boards[board] = value

    def warned(self, res: Result, needle: str) -> bool:
        return any(needle in w for w in res.data["warnings"])


class BandPickTests(ScoreCase):
    def test_plan_claude_wins_its_band(self) -> None:
        res = self.pick("--band", "haiku")
        self.assertEqual(res.code, 0)
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertEqual(res.data["pick"]["cost_usd"], 0)
        self.assertEqual(res.data["pick"]["harness"], "claude-code")
        self.assertEqual(res.data["pick"]["channel"], "agent")
        self.assertEqual(res.data["mix_band"], "haiku")

    def test_lowest_index_cost_plan_variant_wins(self) -> None:
        res = self.pick("--band", "bulk")
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertEqual(res.data["pick"]["banded_effort"], "medium")

    def test_metered_ranks_by_aai_over_cost(self) -> None:
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        pick = res.data["pick"]
        self.assertEqual(pick["id"], GLM)
        self.assertEqual(pick["banded_effort"], "high")
        self.assertAlmostEqual(pick["value"], 29.0 / 1500)
        self.assertAlmostEqual(pick["cost_usd"], 1500)

    def test_cost_is_repriced_to_channel_price(self) -> None:
        self.reg["hosts"]["h1"]["roster"][GLM]["price"] = {
            "input": 1.68,
            "output": 5.28,
        }
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertAlmostEqual(res.data["pick"]["cost_usd"], 3000)

    def test_bedrock_is_metered(self) -> None:
        res = self.pick("--band", "haiku", env={"CLAUDE_CODE_USE_BEDROCK": "1"})
        self.assertEqual(res.data["profile"], "claude-code-bedrock")
        self.assertAlmostEqual(res.data["pick"]["cost_usd"], 100)
        self.assertEqual(res.data["pick"]["id"], HAIKU)

    def test_track_only_never_enters_a_pick(self) -> None:
        self.reg["overrides"][GLM] = {"track_only": True}
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertNotEqual((res.data["pick"] or {}).get("id"), GLM)
        self.assertNotEqual((res.data["degrade"] or {}).get("id"), GLM)

    def test_unvalued_variant_ranks_after_valued_with_warning(self) -> None:
        self.reg["models"][GLM]["variants"] = {"off": _variant(30.0, None)}
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertEqual(res.data["pick"]["id"], GLM)
        self.assertTrue(self.warned(res, "no index cost"))

    def test_pi_level_not_in_pi_levels_is_skipped_with_warning(self) -> None:
        self.reg["models"][GLM]["variants"]["medium"] = _variant(30.0, 1)
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertNotEqual(res.data["pick"]["banded_effort"], "medium")
        self.assertTrue(self.warned(res, "pi level"))

    def test_single_effort_sends_high_when_listed(self) -> None:
        self.reg["models"][GLM]["variants"] = {"single": _variant(30.0, 100)}
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertEqual(res.data["pick"]["banded_effort"], "single")
        self.assertIn("--thinking high", res.data["pick"]["command"])

    def test_single_effort_without_high_uses_top_level(self) -> None:
        self.reg["hosts"]["h1"]["roster"][GLM]["pi_levels"] = ["low", "max"]
        self.reg["models"][GLM]["variants"] = {"single": _variant(30.0, 100)}
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertIn("--thinking max", res.data["pick"]["command"])

    def test_empty_pi_levels_sends_high_without_warning(self) -> None:
        self.reg["hosts"]["h1"]["roster"][GLM]["pi_levels"] = []
        self.reg["models"][GLM]["variants"] = {"single": _variant(30.0, 100)}
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertIn("--thinking high", res.data["pick"]["command"])
        self.assertFalse(self.warned(res, "pi level"))

    def test_placement_supplies_aai_with_low_confidence_warning(self) -> None:
        self.drop_roster(GPTX)
        self.reg["models"][QWEN] = _model({}, PRICE)
        self.reg["hosts"]["h1"]["roster"][QWEN] = _pi_entry(QWEN, ["pi-zdr"])
        self.reg["overrides"][QWEN] = {
            "placements": {"high": {"aai": 41.0, "confidence": "low"}}
        }
        res = self.pick("--band", "sonnet", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertEqual(res.data["pick"]["id"], QWEN)
        self.assertEqual(res.data["pick"]["confidence"], "low")
        self.assertTrue(self.warned(res, "low confidence"))

    def test_stored_band_is_not_trusted(self) -> None:
        self.reg["models"][HAIKU]["variants"]["high"]["band"] = "opus"
        res = self.pick("--band", "opus")
        self.assertEqual(res.data["pick"]["id"], OPUS)


class EmptyBandTests(ScoreCase):
    def test_empty_band_steps_up_with_warning(self) -> None:
        self.drop_roster(SONNET, GPTX)
        res = self.pick("--band", "sonnet")
        self.assertEqual(res.data["pick"]["id"], OPUS)
        self.assertTrue(self.warned(res, "band sonnet empty; stepped up to opus"))
        self.assertEqual(res.data["mix_band"], "opus")

    def test_never_steps_into_mythos(self) -> None:
        self.drop_roster(OPUS)
        res = self.pick("--band", "opus")
        self.assertIsNone(res.data["pick"])
        self.assertEqual(res.code, 3)
        self.assertIsNone(res.data["degrade"])
        self.assertNotIn(FABLE, json.dumps(res.data["pick"]))

    def test_pi_zdr_empty_sonnet_drops_to_best_haiku(self) -> None:
        self.drop_roster(GPTX)
        res = self.pick("--band", "sonnet", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertEqual(res.code, 0)
        self.assertIsNone(res.data["pick"])
        self.assertEqual(res.data["degrade"]["id"], GLM)
        self.assertEqual(res.data["degrade"]["banded_effort"], "high")
        self.assertTrue(self.warned(res, "degrade to"))
        self.assertTrue(self.warned(res, "band sonnet empty"))
        self.assertEqual(res.data["mix_band"], "haiku")

    def test_nothing_at_all_exits_3_with_json(self) -> None:
        self.drop_roster(OPUS)
        res = self.pick("--band", "opus")
        self.assertEqual(res.code, 3)
        self.assertIsNone(res.data["degrade"])


class TagTests(ScoreCase):
    def test_ci_margin_reroutes_when_intervals_do_not_overlap(self) -> None:
        self.allow_reroute()
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["pick"]["id"], GLM)
        self.assertEqual(res.data["tag"], "design")

    def test_ci_margin_keeps_plan_when_intervals_overlap(self) -> None:
        self.set_board(GLM, "arena_webdev", _board(1505, 5))
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["pick"]["id"], HAIKU)

    def test_numeric_margin_keeps_competitive_set(self) -> None:
        res = self.pick("--band", "haiku", "--tag", "eq")
        self.assertEqual(res.data["pick"]["id"], HAIKU)

    def test_numeric_margin_excludes_outside_margin(self) -> None:
        self.allow_reroute()
        self.set_board(GLM, "eq_bench", _board(85))
        res = self.pick("--band", "haiku", "--tag", "eq")
        self.assertEqual(res.data["pick"]["id"], GLM)

    def test_missing_score_returns_untagged_pick_with_warning(self) -> None:
        self.set_board(HAIKU, "arena_webdev", None)
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertTrue(
            self.warned(res, f"tag design has no score for {HAIKU}; not routing away")
        )

    def test_language_tag_narrows_after_skill_tag(self) -> None:
        self.allow_reroute()
        self.set_board(GLM, "arena_webdev", _board(1500, 5))
        self.set_board(HAIKU, "arena_chinese", _board(1400, 5))
        res = self.pick("--band", "haiku", "--tag", "design", "--lang", "chinese")
        self.assertEqual(res.data["lang"], "chinese")
        self.assertEqual(res.data["pick"]["id"], GLM)

    def test_language_cannot_resurrect_model_cut_by_skill_tag(self) -> None:
        self.set_board(GLM, "arena_webdev", _board(1000, 5))
        self.set_board(HAIKU, "arena_chinese", _board(1400, 5))
        res = self.pick("--band", "haiku", "--tag", "design", "--lang", "chinese")
        self.assertEqual(res.data["pick"]["id"], HAIKU)

    def test_unknown_tag_is_a_usage_error(self) -> None:
        res = self.pick("--band", "haiku", "--tag", "nope")
        self.assertEqual(res.code, 2)
        self.assertIn("unknown specialty tag 'nope'", res.err)

    def test_unknown_language_is_a_usage_error(self) -> None:
        res = self.pick("--band", "haiku", "--lang", "design")
        self.assertEqual(res.code, 2)
        self.assertIn("unknown language group 'design'", res.err)

    def test_on_refusal_is_other_vendor_never_anthropic(self) -> None:
        res = self.pick("--band", "sonnet", "--tag", "cyber")
        self.assertEqual(res.data["pick"]["id"], SONNET)
        self.assertEqual(res.data["on_refusal"]["id"], GPTX)

    def test_on_refusal_skips_anthropic_even_when_best(self) -> None:
        self.set_cost(SONNET, "high", 400)
        self.set_cost(SONNET, "medium", 400)
        self.set_board(SONNET, "aa_cyber", _board(70))
        res = self.pick("--band", "sonnet", "--tag", "cyber")
        self.assertEqual(res.data["pick"]["id"], GPTX)
        self.assertIsNone(res.data["on_refusal"])

    def test_on_refusal_null_without_reroute_flag(self) -> None:
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertIsNone(res.data["on_refusal"])


class CostCeilingTests(ScoreCase):
    """A tag may not move a pick to a variant over 1.5x the untagged cost."""

    PI: ClassVar[dict[str, str]] = {"MODEL_SELECTION_HARNESS": "pi"}

    def claude_only(self) -> None:
        for model_id in (GLM, DSEEK, GPTX, FABLE):
            self.drop_roster(model_id)
            del self.reg["models"][model_id]

    def writing_case(self, opus_cost: float) -> None:
        """Haiku high is the untagged pick; Opus low wins writing by far."""
        self.claude_only()
        self.reg["models"][HAIKU]["variants"]["high"]["index_cost_usd"] = 121
        self.reg["models"][OPUS]["variants"]["low"] = _variant(35.0, opus_cost)
        self.set_board(HAIKU, "arena_writing", _board(1337, 5))
        self.set_board(OPUS, "arena_writing", _board(1532, 5))

    def test_cap_keeps_cheap_pick_and_warns(self) -> None:
        self.writing_case(980)
        res = self.pick("--band", "haiku", "--tag", "writing")
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertEqual(res.data["pick"]["banded_effort"], "high")
        self.assertTrue(
            self.warned(res, f"tag writing would pick {OPUS} low at 8.1x the")
        )
        self.assertTrue(self.warned(res, "capped at 1.5x"))

    def test_variant_inside_the_cap_may_still_win(self) -> None:
        self.writing_case(121 * 1.4)
        res = self.pick("--band", "haiku", "--tag", "writing")
        self.assertEqual(res.data["pick"]["id"], OPUS)
        self.assertFalse(self.warned(res, "capped at"))

    def test_cap_warning_appears_once(self) -> None:
        self.writing_case(980)
        res = self.pick("--band", "haiku", "--tag", "writing")
        warns = res.data["warnings"]
        self.assertEqual(len(warns), len(set(warns)))
        self.assertEqual(sum("would pick" in w for w in warns), 1)

    def test_comparison_run_leaves_no_warnings_behind(self) -> None:
        self.writing_case(980)
        self.set_board(HAIKU, "arena_writing", None)
        res = self.pick("--band", "haiku", "--tag", "writing")
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertFalse(self.warned(res, "would pick"))
        self.assertEqual(sum("has no score" in w for w in res.data["warnings"]), 1)

    def test_role_rank_on_tag_is_capped(self) -> None:
        self.claude_only()
        self.reg["models"][OPUS]["variants"]["low"] = _variant(41.0, 500)
        self.set_board(SONNET, "tb4", _board(0.4))
        res = self.pick("--role", "coordinator")
        self.assertEqual(res.data["pick"]["id"], SONNET)
        self.assertEqual(res.data["pick"]["banded_effort"], "medium")
        self.assertTrue(self.warned(res, f"tag long-horizon would pick {OPUS} low"))

    def pi_unpriced(self) -> None:
        """Both haiku-band GLM variants and DSEEK have no cost; DSEEK scores best."""
        self.reg["hosts"]["h1"]["roster"][DSEEK]["rosters"] = ["pi-zdr"]
        for model_id in (GLM, DSEEK):
            for var in self.reg["models"][model_id]["variants"].values():
                var["index_cost_usd"] = None
        self.set_board(DSEEK, "arena_webdev", _board(1700, 5))

    def test_unknown_base_cost_applies_no_cap_and_warns(self) -> None:
        self.pi_unpriced()
        res = self.pick("--band", "haiku", "--tag", "design", env=self.PI)
        self.assertEqual(res.data["pick"]["id"], DSEEK)
        self.assertTrue(self.warned(res, "tag cost ceiling not applied"))

    def pi_free(self, rival_cost: float) -> None:
        """GLM max is free; DSEEK scores best on design at `rival_cost`."""
        self.reg["hosts"]["h1"]["roster"][DSEEK]["rosters"] = ["pi-zdr"]
        self.reg["models"][GLM]["variants"]["max"]["index_cost_usd"] = 0
        self.reg["models"][DSEEK]["variants"]["max"]["index_cost_usd"] = rival_cost
        self.set_board(DSEEK, "arena_webdev", _board(1700, 5))

    def test_zero_base_cost_lets_only_free_variants_pass(self) -> None:
        self.pi_free(500)
        res = self.pick("--band", "haiku", "--tag", "design", env=self.PI)
        self.assertEqual(res.data["pick"]["id"], GLM)
        self.assertEqual(res.data["pick"]["banded_effort"], "max")
        self.assertTrue(self.warned(res, f"tag design would pick {DSEEK} max"))

    def test_zero_base_cost_passes_another_free_variant(self) -> None:
        self.pi_free(0)
        res = self.pick("--band", "haiku", "--tag", "design", env=self.PI)
        self.assertEqual(res.data["pick"]["id"], DSEEK)
        self.assertFalse(self.warned(res, "capped"))


class CostEstimateTests(ScoreCase):
    """A subscription variant with no index cost gets an estimated one."""

    def claude_only(self) -> None:
        for model_id in (GLM, DSEEK, GPTX, FABLE):
            self.drop_roster(model_id)
            del self.reg["models"][model_id]

    def test_estimate_scales_the_same_models_other_effort(self) -> None:
        self.claude_only()
        models = self.reg["models"]
        models[HAIKU]["variants"]["max"] = _variant(31.0, None)
        models[SONNET]["variants"]["max"] = _variant(42.0, 150)
        models[OPUS]["variants"]["max"] = _variant(52.0, 450)
        res = self.pick("--band", "haiku")
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertEqual(res.data["pick"]["banded_effort"], "max")
        self.assertTrue(self.warned(res, "estimated ($50)"))

    def test_estimate_uses_cross_model_median_without_a_measured_effort(self) -> None:
        self.claude_only()
        self.reg["models"][HAIKU]["variants"]["high"]["index_cost_usd"] = 1000
        self.reg["models"]["new/model"] = _model(
            {"high": _variant(30.0, None)}, CLAUDE_PRICE
        )
        self.reg["hosts"]["h1"]["roster"]["new/model"] = _claude_entry("new")
        res = self.pick("--band", "haiku")
        self.assertEqual(res.data["pick"]["id"], "new/model")
        self.assertTrue(self.warned(res, "estimated ($900)"))

    def test_nothing_to_estimate_from_ranks_last(self) -> None:
        self.claude_only()
        self.reg["models"]["new/model"] = _model(
            {"max": _variant(30.0, None)}, CLAUDE_PRICE
        )
        self.reg["hosts"]["h1"]["roster"]["new/model"] = _claude_entry("new")
        res = self.pick("--band", "haiku")
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertFalse(self.warned(res, "estimated"))


class MythosTests(ScoreCase):
    def test_band_mythos_ranks_but_never_picks(self) -> None:
        res = self.pick("--band", "mythos")
        self.assertIsNone(res.data["pick"])
        self.assertEqual(res.code, 3)
        self.assertTrue(self.warned(res, "mythos is directive-only"))
        self.assertEqual(res.data["ranked"][0]["id"], FABLE)

    def test_model_flag_makes_mythos_a_directive_pick(self) -> None:
        res = self.pick("--band", "mythos", "--model", FABLE)
        self.assertEqual(res.code, 0)
        self.assertEqual(res.data["pick"]["id"], FABLE)

    def test_user_named_picks_best_mythos_and_exits_0(self) -> None:
        res = self.pick("--band", "mythos", "--user-named")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["band"], "mythos")
        self.assertEqual(res.data["pick"]["id"], FABLE)
        self.assertFalse(self.warned(res, "directive-only"))

    def test_user_named_respects_effort(self) -> None:
        res = self.pick("--band", "mythos", "--user-named", "--effort", "xhigh")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["pick"]["effort"], "xhigh")

    def test_user_named_leaves_other_bands_unchanged(self) -> None:
        plain = self.pick("--band", "sonnet")
        named = self.pick("--band", "sonnet", "--user-named")
        self.assertEqual(named.code, 0)
        self.assertEqual(named.data, plain.data)


class FableFamilyTests(ScoreCase):
    """A new Fable version is mythos with no edit to the policy list."""

    def setUp(self) -> None:
        super().setUp()
        self.reg["policy"]["bands"]["mythos"] = ["anthropic/claude-fable-*"]
        self.reg["models"][FABLE2] = _model(
            {"high": _variant(64.0, 1500), "xhigh": _variant(66.0, 1800)},
            CLAUDE_PRICE,
        )
        for host in self.reg["hosts"].values():
            host["roster"][FABLE2] = _claude_entry("fable")

    def test_user_named_mythos_picks_the_newest_fable(self) -> None:
        res = self.pick("--band", "mythos", "--user-named", "--effort", "xhigh")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["pick"]["id"], FABLE2)

    def test_new_fable_is_never_auto_picked_though_its_score_tops_opus(self) -> None:
        for band, want in (("opus", OPUS), ("sonnet", SONNET)):
            with self.subTest(band=band):
                self.assertEqual(self.pick("--band", band).data["pick"]["id"], want)

    def test_listing_ranks_both_fables_and_picks_none(self) -> None:
        res = self.pick("--band", "mythos")
        self.assertEqual(res.code, 3)
        self.assertEqual({r["id"] for r in res.data["ranked"]}, {FABLE, FABLE2})
        self.assertIsNone(res.data["pick"])


class ConsultantTests(ScoreCase):
    def test_steps_band_and_effort_up(self) -> None:
        res = self.pick("--consultant-for", "sonnet:high")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["band"], "opus")
        self.assertEqual(res.data["pick"]["id"], OPUS)
        self.assertEqual(res.data["pick"]["effort"], "xhigh")
        self.assertEqual(res.data["consultant_for"], "sonnet:high")

    def test_band_caps_at_opus_and_effort_at_max(self) -> None:
        for creator in ("opus:max", "mythos:max"):
            res = self.pick("--consultant-for", creator)
            self.assertEqual(res.code, 0, res.err)
            self.assertEqual(res.data["band"], "opus", creator)
            self.assertEqual(res.data["pick"]["effort"], "max", creator)

    def test_lowest_levels_step_up_one(self) -> None:
        res = self.pick("--consultant-for", "bulk:off")
        self.assertEqual(res.data["band"], "haiku")
        self.assertEqual(res.data["pick"]["effort"], "minimal")

    def test_conflicting_flags_exit_2(self) -> None:
        for extra in (
            ("--band", "opus"),
            ("--role", "coordinator"),
            ("--effort", "high"),
            ("--model", OPUS),
        ):
            res = self.pick("--consultant-for", "sonnet:high", *extra)
            self.assertEqual(res.code, 2, extra)
            self.assertIn("--consultant-for", res.err, extra)

    def test_unknown_band_or_effort_exits_2(self) -> None:
        for bad in ("nope:high", "sonnet:nope", "sonnet", "single:high"):
            self.assertEqual(self.pick("--consultant-for", bad).code, 2, bad)


class ExecutiveRoleTests(ScoreCase):
    def test_executive_falls_back_to_orchestrator_entry(self) -> None:
        res = self.pick("--role", "executive")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["role"], "executive")
        self.assertEqual(res.data["band"], "opus")
        self.assertEqual(res.data["pick"]["effort"], "xhigh")

    def test_executive_entry_wins_when_present(self) -> None:
        roles = self.reg["policy"]["roles"]
        roles["executive"] = {"band": "sonnet", "effort": "high"}
        res = self.pick("--role", "executive")
        self.assertEqual(res.data["band"], "sonnet")
        self.assertEqual(res.data["pick"]["effort"], "high")

    def test_orchestrator_is_an_alias_for_the_executive_entry(self) -> None:
        roles = self.reg["policy"]["roles"]
        roles["executive"] = {"band": "sonnet", "effort": "high"}
        del roles["orchestrator"]
        res = self.pick("--role", "orchestrator")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["role"], "orchestrator")
        self.assertEqual(res.data["band"], "sonnet")
        self.assertEqual(res.data["pick"]["effort"], "high")

    def test_orchestrator_still_works(self) -> None:
        res = self.pick("--role", "orchestrator")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["role"], "orchestrator")


class EffortTests(ScoreCase):
    def test_claude_pick_defaults_to_medium(self) -> None:
        res = self.pick("--band", "sonnet")
        self.assertEqual(res.data["pick"]["effort"], "medium")

    def test_role_sets_band_and_effort(self) -> None:
        res = self.pick("--role", "orchestrator")
        pick = res.data["pick"]
        self.assertEqual(res.data["role"], "orchestrator")
        self.assertEqual(res.data["band"], "opus")
        self.assertEqual(pick["id"], OPUS)
        self.assertEqual(pick["banded_effort"], "high")
        self.assertEqual(pick["effort"], "xhigh")

    def test_coordinator_role_is_sonnet_at_high(self) -> None:
        res = self.pick("--role", "coordinator")
        self.assertEqual(res.code, 0, res.err)
        self.assertEqual(res.data["band"], "sonnet")
        self.assertEqual(res.data["pick"]["effort"], "high")

    def test_retired_hierarchy_roles_exit_2_naming_coordinator(self) -> None:
        # A registry installed before hierarchy v2 still lists "lead".
        self.reg["policy"]["roles"]["lead"] = {"band": "opus", "effort": "high"}
        for role in ("lead", "subdomain", "subdomain-coordinator"):
            res = self.pick("--role", role)
            self.assertEqual(res.code, 2, role)
            self.assertIn("--role coordinator", res.err, role)

    def test_worker_role_needs_a_band(self) -> None:
        self.assertEqual(self.pick("--role", "worker").code, 2)
        res = self.pick("--role", "worker", "--band", "haiku")
        self.assertEqual(res.data["pick"]["effort"], "medium")

    def test_role_effort_never_lifts_pick_out_of_its_band(self) -> None:
        self.reg["models"][OPUS]["variants"]["low"] = _variant(35.0, 10)
        self.reg["models"][OPUS]["variants"]["medium"] = _variant(48.0, 20)
        res = self.pick("--band", "haiku")
        pick = res.data["pick"]
        self.assertEqual((pick["id"], pick["banded_effort"]), (OPUS, "low"))
        self.assertEqual(pick["effort"], "low")
        self.assertTrue(self.warned(res, "out of band haiku"))

    def test_role_effort_raises_when_band_holds(self) -> None:
        self.reg["models"][OPUS]["variants"]["low"] = _variant(35.0, 10)
        self.reg["models"][OPUS]["variants"]["medium"] = _variant(38.0, 20)
        res = self.pick("--band", "haiku")
        self.assertEqual(res.data["pick"]["effort"], "medium")

    def test_pi_pick_uses_banded_effort(self) -> None:
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertEqual(res.data["pick"]["effort"], "high")
        self.assertIn("--thinking high", res.data["pick"]["command"])

    def test_effort_flag_overrides(self) -> None:
        res = self.pick("--band", "sonnet", "--effort", "max")
        self.assertEqual(res.data["pick"]["effort"], "max")
        self.assertEqual(res.data["pick"]["banded_effort"], "medium")

    def test_pi_thinking_override_changes_thinking_flag(self) -> None:
        res = self.pick(
            "--band", "haiku", env={"MODEL_SELECTION_PROFILE": "pi-permissive"}
        )
        pick = res.data["pick"]
        self.assertEqual(pick["id"], DSEEK)
        self.assertEqual(pick["banded_effort"], "max")
        self.assertIn("--thinking high", pick["command"])
        self.assertTrue(self.warned(res, "placeholder"))


class ChannelTests(ScoreCase):
    def setUp(self) -> None:
        super().setUp()
        self.allow_reroute()

    def test_every_pi_command_ends_in_dev_null(self) -> None:
        for env in ({"MODEL_SELECTION_HARNESS": "pi"}, {"HERDR_ENV": "1"}, {}):
            res = self.pick("--band", "haiku", "--tag", "design", env=env)
            self.assertTrue(res.data["pick"]["command"].endswith("< /dev/null"))

    def test_cross_harness_pick_uses_herdr_when_env_set(self) -> None:
        res = self.pick("--band", "haiku", "--tag", "design", env={"HERDR_ENV": "1"})
        self.assertEqual(res.data["pick"]["harness"], "pi")
        self.assertEqual(res.data["pick"]["channel"], "herdr")

    def test_cross_harness_pick_uses_shell_without_herdr(self) -> None:
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["pick"]["channel"], "shell")

    def test_pi_pick_in_pi_profile_is_in_process(self) -> None:
        res = self.pick("--band", "haiku", env={"MODEL_SELECTION_HARNESS": "pi"})
        self.assertEqual(res.data["pick"]["channel"], "pi")

    def test_fallback_is_primary_harness_variant_in_band(self) -> None:
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["fallback"]["id"], HAIKU)

    def test_no_fallback_when_pick_is_primary_harness(self) -> None:
        res = self.pick("--band", "haiku")
        self.assertIsNone(res.data["fallback"])

    def test_unhealthy_harness_is_skipped_with_warning(self) -> None:
        self.reg["hosts"]["h1"]["harnesses"]["claude-code"]["healthy"] = False
        res = self.pick("--band", "haiku")
        self.assertEqual(res.data["pick"]["harness"], "pi")
        self.assertTrue(self.warned(res, "claude-code"))


class ProfileTests(ScoreCase):
    def source(self, env: dict[str, str], *args: str) -> tuple[str, str]:
        res = self.pick("--band", "haiku", *args, env=env)
        return res.data["profile"], res.data["profile_source"]

    def test_flag_wins(self) -> None:
        env = {"MODEL_SELECTION_PROFILE": "pi-zdr", "CLAUDECODE": "1"}
        self.assertEqual(
            self.source(env, "--profile", "claude-code"),
            ("claude-code", "--profile"),
        )

    def test_env_profile_second(self) -> None:
        env = {"MODEL_SELECTION_PROFILE": "pi-zdr", "CLAUDE_CODE_USE_BEDROCK": "1"}
        self.assertEqual(self.source(env), ("pi-zdr", "MODEL_SELECTION_PROFILE"))

    def test_bedrock_after_pi(self) -> None:
        env = {"CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDECODE": "1"}
        self.assertEqual(
            self.source(env), ("claude-code-bedrock", "CLAUDE_CODE_USE_BEDROCK")
        )

    def test_claudecode_after_bedrock(self) -> None:
        self.assertEqual(
            self.source({"CLAUDECODE": "1"}), ("claude-code", "CLAUDECODE")
        )

    def test_pi_under_claude_code_is_pi(self) -> None:
        for env in (
            {"CLAUDECODE": "1", "MODEL_SELECTION_HARNESS": "pi"},
            {"CLAUDECODE": "1", "PI_CODING_AGENT": "true"},
            {"CLAUDECODE": "1", "CLAUDE_CODE_USE_BEDROCK": "1", "PI_CODING_AGENT": "1"},
        ):
            self.assertEqual(self.source(env)[0], "pi-zdr", env)

    def test_pi_harness_markers(self) -> None:
        self.assertEqual(
            self.source({"MODEL_SELECTION_HARNESS": "pi"}),
            ("pi-zdr", "MODEL_SELECTION_HARNESS"),
        )
        self.assertEqual(
            self.source({"PI_CODING_AGENT": "1"}), ("pi-zdr", "PI_CODING_AGENT")
        )

    def test_host_default_last(self) -> None:
        self.reg["hosts"]["h1"]["default_profile"] = "pi-zdr"
        self.assertEqual(self.source({}), ("pi-zdr", "host default_profile"))

    def test_unknown_profile_is_usage_error(self) -> None:
        self.assertEqual(self.pick("--band", "haiku", "--profile", "zzz").code, 2)

    def test_unknown_host_falls_back_with_warning(self) -> None:
        res = self.call("--pick", "--band", "sonnet", host="nope")
        self.assertEqual(res.code, 0)
        self.assertTrue(self.warned(res, "unknown host nope"))
        self.assertEqual(res.data["pick"]["harness"], "claude-code")

    def test_unknown_host_has_no_pi(self) -> None:
        res = self.call(
            "--pick",
            "--band",
            "haiku",
            "--tag",
            "design",
            host="nope",
            env={"HERDR_ENV": "1"},
        )
        self.assertEqual(res.data["pick"]["harness"], "claude-code")


class WarningTests(ScoreCase):
    def test_stale_models_store_warns(self) -> None:
        res = self.call("--pick", "--band", "haiku", "--today", "2026-11-20")
        self.assertTrue(self.warned(res, "pi_models_store"))

    def test_fresh_models_store_is_quiet(self) -> None:
        res = self.pick("--band", "haiku")
        self.assertFalse(self.warned(res, "pi_models_store"))

    def test_failed_source_warns(self) -> None:
        self.reg["sources"]["aa_free"] = {"status": "failed", "as_of": "2026-11-09"}
        res = self.pick("--band", "haiku")
        self.assertTrue(self.warned(res, "aa_free"))

    def test_old_source_warns_stale(self) -> None:
        self.reg["sources"]["aa_free"] = {"status": "ok", "as_of": "2026-10-01"}
        res = self.pick("--band", "haiku")
        self.assertTrue(self.warned(res, "aa_free"))

    def test_unrelated_failed_board_is_quiet(self) -> None:
        self.reg["sources"]["arena_webdev"] = {"status": "failed"}
        res = self.pick("--band", "haiku")
        self.assertFalse(self.warned(res, "arena_webdev"))

    def test_failed_board_of_requested_tag_warns(self) -> None:
        self.reg["sources"]["arena_webdev"] = {"status": "failed"}
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertTrue(self.warned(res, "arena_webdev"))

    def test_role_warns_on_its_ranking_feed(self) -> None:
        self.reg["sources"]["aa_page_lcr"] = {"status": "failed"}
        res = self.pick("--role", "orchestrator")
        self.assertTrue(self.warned(res, "aa_page_lcr"))

    def test_retired_source_is_quiet(self) -> None:
        self.reg["sources"]["aa_api"] = {"status": "retired", "as_of": "2026-01-01"}
        res = self.pick("--band", "haiku")
        self.assertFalse(self.warned(res, "aa_api"))


class UsageTests(ScoreCase):
    def test_retired_flags_exit_2_and_name_new_interface(self) -> None:
        for args in (
            ("--pick", "--system", "x"),
            ("--pick", "--tier", "2"),
            ("--pick", "--profile", "coding"),
            ("--pick", "--profile", "reasoning"),
            ("--pick", "--profile", "style"),
        ):
            res = self.call(*args)
            self.assertEqual(res.code, 2, args)
            self.assertIn("--pick --band", res.err)
            self.assertEqual(res.out, "")

    def test_pick_needs_band_or_role(self) -> None:
        self.assertEqual(self.pick().code, 2)

    def test_unknown_band_is_usage_error(self) -> None:
        self.assertEqual(self.pick("--band", "huge").code, 2)

    def test_missing_registry_exits_2(self) -> None:
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = score.main(
                ["--pick", "--band", "haiku", "--registry", "/nope.json"], {}
            )
        self.assertEqual(code, 2)

    def test_no_mode_exits_2(self) -> None:
        self.assertEqual(self.call().code, 2)

    def test_table_prints_every_band(self) -> None:
        res = self.call("--table", "--profile", "claude-code")
        self.assertEqual(res.code, 0)
        for needle in ("bulk", "haiku", "sonnet", "opus", "mythos", HAIKU, GLM):
            self.assertIn(needle, res.out)


class RepairTests(ScoreCase):
    PI: ClassVar[dict[str, str]] = {"MODEL_SELECTION_HARNESS": "pi"}

    def add_qwen(self, aai: float, cost: float, boards: Reg | None = None) -> None:
        self.reg["models"][QWEN] = _model(
            {"high": _variant(aai, cost)}, PRICE, boards or {}
        )
        self.reg["hosts"]["h1"]["roster"][QWEN] = _pi_entry(QWEN, ["pi-zdr"])

    def test_m2_pi_effort_is_the_thinking_level(self) -> None:
        self.reg["models"][GLM]["variants"] = {"single": _variant(30.0, 100)}
        pick = self.pick("--band", "haiku", env=self.PI).data["pick"]
        self.assertEqual(pick["banded_effort"], "single")
        self.assertEqual(pick["effort"], "high")
        self.reg["hosts"]["h1"]["roster"][DSEEK]["rosters"] = ["pi-zdr"]
        res = self.pick("--band", "haiku", "--effort", "max", env=self.PI)
        self.assertEqual(res.data["pick"]["effort"], "max")

    def test_m2_override_remap_shows_in_effort(self) -> None:
        res = self.pick(
            "--band", "haiku", env={"MODEL_SELECTION_PROFILE": "pi-permissive"}
        )
        self.assertEqual(res.data["pick"]["effort"], "high")
        self.assertEqual(res.data["pick"]["banded_effort"], "max")

    def test_m3_mythos_alias_in_roster_is_never_picked(self) -> None:
        alias = "anthropic/claude-fable-5.1"
        self.reg["models"][alias] = _model({"high": _variant(55.0, 10)}, PRICE)
        self.reg["hosts"]["h1"]["roster"][alias] = _pi_entry(alias, ["pi-zdr"])
        for band in ("opus", "sonnet"):
            res = self.pick("--band", band, env=self.PI)
            ids = [(res.data[k] or {}).get("id") for k in ("pick", "degrade")]
            self.assertNotIn(alias, ids, band)

    def test_m6_drop_gets_on_refusal(self) -> None:
        self.drop_roster(GPTX)
        self.add_qwen(30.0, 3000, {"aa_cyber": _board(70)})
        res = self.pick("--band", "sonnet", "--tag", "cyber", env=self.PI)
        self.assertIsNone(res.data["pick"])
        self.assertEqual(res.data["degrade"]["id"], GLM)
        self.assertEqual(res.data["on_refusal"]["id"], QWEN)

    def test_m1_effort_flag_is_validated(self) -> None:
        for bad in ("bogus", "single", "high; touch /tmp/x #"):
            res = self.pick("--band", "haiku", "--effort", bad, env=self.PI)
            self.assertEqual(res.code, 2, bad)
            self.assertEqual(res.out, "")

    def test_m2_shell_values_are_quoted(self) -> None:
        ref = "openrouter/z-ai/glm'; touch /tmp/x; echo '"
        self.reg["hosts"]["h1"]["roster"][GLM]["model_ref"] = ref
        cmd = self.pick("--band", "haiku", env=self.PI).data["pick"]["command"]
        self.assertEqual(shlex.split(cmd)[2], ref)
        self.assertTrue(cmd.endswith("< /dev/null"))

    def test_m3_bad_registry_content_exits_2_one_line(self) -> None:
        del self.reg["hosts"]["h1"]["default_profile"]
        res = self.pick("--band", "haiku")
        self.assertEqual(res.code, 2)
        self.assertEqual(len(res.err.strip().splitlines()), 1)
        self.assertNotIn("Traceback", res.err)

    def test_m3_validate_errors_exit_2(self) -> None:
        self.reg["models"][HAIKU]["variants"]["high"]["aai"] = "x"
        self.reg["policy"]["bands"]["order"] = []
        res = self.pick("--band", "haiku")
        self.assertEqual(res.code, 2)
        self.assertEqual(len(res.err.strip().splitlines()), 1)

    def test_m4_free_metered_variant_ranks_first(self) -> None:
        self.reg["models"][GLM]["variants"]["high"]["index_cost_usd"] = 0
        pick = self.pick("--band", "haiku", env=self.PI).data["pick"]
        self.assertEqual((pick["id"], pick["banded_effort"]), (GLM, "high"))
        self.assertEqual(pick["cost_usd"], 0)

    def test_m5_aged_board_source_is_ignored(self) -> None:
        self.reg["sources"]["arena_webdev"] = {"status": "ok", "as_of": "2026-01-01"}
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["pick"]["id"], HAIKU)
        self.assertTrue(self.warned(res, "older than 90 days"))

    def test_m5_fresh_board_source_still_routes(self) -> None:
        self.allow_reroute()
        self.reg["sources"]["arena_webdev"] = {"status": "ok", "as_of": "2026-11-01"}
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["pick"]["id"], GLM)

    def test_m5_aged_aai_source_is_ignored(self) -> None:
        self.reg["sources"]["aa_free"] = {"status": "ok", "as_of": "2026-01-01"}
        res = self.pick("--band", "haiku")
        self.assertEqual(res.code, 3)
        self.assertTrue(self.warned(res, "older than 90 days"))

    def test_mix_band_is_the_pick_band_not_the_dispatched_effort(self) -> None:
        res = self.pick("--band", "haiku")
        self.assertEqual(res.data["pick"]["effort"], "medium")
        self.assertEqual(res.data["mix_band"], "haiku")

    def test_mix_band_follows_a_drop(self) -> None:
        res = self.pick("--band", "opus", env=self.PI)
        self.assertIsNone(res.data["pick"])
        self.assertEqual(res.data["degrade"]["id"], GPTX)
        self.assertEqual(res.data["mix_band"], "sonnet")

    def test_m11_tiebreak_decides_equal_values(self) -> None:
        self.drop_roster(GPTX)
        self.reg["models"][GLM]["variants"] = {"high": _variant(29.0, 1500)}
        self.set_board(GLM, "tb4", _board(0.9))
        self.set_board(GLM, "eq_bench", _board(75))
        self.add_qwen(29.0, 1500, {"eq_bench": _board(75), "tb4": _board(0.2)})
        plain = self.pick("--band", "haiku", env=self.PI).data["pick"]["id"]
        tied = self.pick("--band", "haiku", "--tag", "tied", env=self.PI)
        self.assertEqual(plain, QWEN)
        self.assertEqual(tied.data["pick"]["id"], GLM)

    def test_m15_primary_key_not_dict_order_decides_channel(self) -> None:
        self.allow_reroute()
        prof = self.reg["policy"]["profiles"]["claude-code"]
        prof["harnesses"] = dict(reversed(list(prof["harnesses"].items())))
        res = self.pick("--band", "haiku")
        self.assertEqual(res.data["pick"]["channel"], "agent")
        prof["primary"] = "pi"
        res = self.pick("--band", "haiku", "--tag", "design")
        self.assertEqual(res.data["pick"]["channel"], "pi")

    def test_m16_payload_flag_is_substituted_quoted(self) -> None:
        res = self.pick("--band", "haiku", "--payload", "/t/my brief.md", env=self.PI)
        cmd = res.data["pick"]["command"]
        self.assertIn("cat '/t/my brief.md'", cmd)
        default = self.pick("--band", "haiku", env=self.PI).data["pick"]["command"]
        self.assertIn("cat payload.md", default)


if __name__ == "__main__":
    unittest.main()
