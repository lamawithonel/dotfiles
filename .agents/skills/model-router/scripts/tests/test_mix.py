#!/usr/bin/env python3
"""Tests for `score.py --mix`: the measured target mix from the dispatch log.

Each test writes a synthetic dispatch log, one JSON object per line as
the log-dispatch hook writes it, and reads the report `score.py` prints.
"""

import json
import os
import unittest
from typing import Any

from test_score import DSEEK, FABLE, GLM, Result, ScoreCase

MIX = {"haiku_or_below": 0.16, "sonnet": 0.64, "opus_or_above": 0.20}


def _rec(model: str, effort: str | None, **extra: Any) -> dict[str, Any]:
    rec = {
        "ts": "2026-11-09T12:00:00Z",
        "session_id": "s1",
        "tool": "Agent",
        "harness": "claude-code",
        "model": model,
        "effort": effort,
    }
    rec.update(extra)
    return rec


def _pi(model: str, thinking: str, **extra: Any) -> dict[str, Any]:
    return _rec(f"openrouter/{model}", thinking, tool="Bash", harness="pi", **extra)


class MixCase(ScoreCase):
    def setUp(self) -> None:
        super().setUp()
        self.reg["policy"]["mix"] = dict(MIX)
        self.log = os.path.join(os.path.dirname(self.path), "dispatches.jsonl")

    def write_log(self, *records: dict[str, Any], raw: str = "") -> None:
        with open(self.log, "w", encoding="utf-8") as f:
            f.writelines(json.dumps(r) + "\n" for r in records)
            f.write(raw)

    def mix(self, *args: str) -> Result:
        return self.call("--mix", "--log", self.log, *args)


class NoLogTests(MixCase):
    def test_missing_log_says_no_dispatch_log_not_zero(self) -> None:
        res = self.mix()
        self.assertEqual(res.code, 3)
        self.assertIn("no dispatch log", res.err)
        self.assertEqual(res.out, "")

    def test_log_path_defaults_under_xdg_state_home(self) -> None:
        state = os.path.dirname(self.path)
        res = self.call("--mix", env={"XDG_STATE_HOME": state})
        self.assertEqual(res.code, 3)
        self.assertIn(
            os.path.join(state, "agents", "model-router", "dispatches.jsonl"),
            res.err,
        )

    def test_log_path_env_override(self) -> None:
        self.write_log(_rec("sonnet", "medium"))
        res = self.call("--mix", env={"MODEL_ROUTER_DISPATCH_LOG": self.log})
        self.assertEqual(res.code, 0)
        self.assertEqual(res.data["dispatches"], 1)

    def test_empty_window_reports_null_shares(self) -> None:
        self.write_log()
        res = self.mix()
        self.assertEqual(res.code, 0)
        self.assertEqual(res.data["dispatches"], 0)
        self.assertIsNone(res.data["mix"]["sonnet"]["share"])


class BandRuleTests(MixCase):
    def band_of(self, rec: dict[str, Any]) -> str:
        self.write_log(rec)
        res = self.mix()
        self.assertEqual(res.code, 0, res.err)
        hits = [b for b, n in res.data["bands"].items() if n]
        self.assertEqual(len(hits), 1, res.data["bands"])
        return hits[0]

    def test_sonnet_worker_at_medium_counts_in_anchor_band(self) -> None:
        self.reg["models"]["anthropic/claude-sonnet-5.5"]["variants"]["medium"] = {
            "aai": 38.0,
            "index_cost_usd": 100,
        }
        self.assertEqual(self.band_of(_rec("sonnet", "medium")), "sonnet")

    def test_effort_above_anchor_counts_where_sent(self) -> None:
        glm = self.reg["models"][GLM]["variants"]
        glm["high"]["aai"] = 27.0
        self.assertEqual(self.band_of(_pi(GLM, "max")), "haiku")
        self.assertEqual(self.band_of(_pi(GLM, "low")), "bulk")

    def test_pi_thinking_override_maps_back_to_banded_effort(self) -> None:
        self.reg["hosts"]["h1"]["roster"][DSEEK]["rosters"] = ["pi-zdr"]
        self.reg["models"][DSEEK]["variants"]["high"]["aai"] = 25.0
        self.assertEqual(self.band_of(_pi(DSEEK, "high")), "haiku")

    def test_full_claude_id_resolves_like_alias(self) -> None:
        self.assertEqual(self.band_of(_rec("claude-opus-5-5", "low")), "opus")

    def test_missing_effort_counts_at_anchor(self) -> None:
        self.assertEqual(self.band_of(_rec("haiku", None)), "haiku")

    def test_shell_claude_counts_as_claude(self) -> None:
        rec = _rec("sonnet", "high", tool="Bash", harness="claude")
        self.assertEqual(self.band_of(rec), "sonnet")


class ReportTests(MixCase):
    def test_shares_targets_and_deviation(self) -> None:
        self.write_log(
            _rec("haiku", "medium"),
            _rec("sonnet", "medium"),
            _rec("sonnet", "high"),
            _rec("opus", "xhigh"),
        )
        res = self.mix()
        mix = res.data["mix"]
        self.assertEqual(mix["sonnet"]["count"], 2)
        self.assertEqual(mix["sonnet"]["share"], 0.5)
        self.assertEqual(mix["sonnet"]["target"], 0.64)
        self.assertAlmostEqual(mix["sonnet"]["deviation"], -0.14)
        self.assertEqual(mix["haiku_or_below"]["count"], 1)
        self.assertEqual(mix["opus_or_above"]["count"], 1)

    def test_mythos_and_unknown_stay_out_of_the_shares(self) -> None:
        self.write_log(
            _rec("sonnet", "high"),
            _rec("fable", "high"),
            _rec("mystery-model", "high"),
        )
        res = self.mix()
        self.assertEqual(res.data["dispatches"], 3)
        self.assertEqual(res.data["bands"]["mythos"], 1)
        self.assertEqual(res.data["bands"]["unknown"], 1)
        self.assertEqual(res.data["unknown_models"], ["mystery-model"])
        self.assertEqual(res.data["mix"]["sonnet"]["share"], 1.0)
        self.assertNotIn(FABLE, res.data["unknown_models"])

    def test_session_filter(self) -> None:
        self.write_log(_rec("sonnet", "high"), _rec("opus", "high", session_id="s2"))
        res = self.mix("--session", "s2")
        self.assertEqual(res.data["dispatches"], 1)
        self.assertEqual(res.data["mix"]["opus_or_above"]["count"], 1)

    def test_days_window(self) -> None:
        self.write_log(
            _rec("sonnet", "high"),
            _rec("opus", "high", ts="2026-11-03T00:00:00Z"),
            _rec("opus", "high", ts="2026-11-02T23:59:59Z"),
        )
        self.assertEqual(self.mix().data["dispatches"], 2)
        self.assertEqual(self.mix("--days", "1").data["dispatches"], 1)

    def test_bad_lines_are_skipped_and_counted(self) -> None:
        self.write_log(_rec("sonnet", "high"), raw='not json\n{"ts": 5}\n')
        res = self.mix()
        self.assertEqual(res.data["dispatches"], 1)
        self.assertEqual(res.data["skipped_lines"], 2)

    def test_days_must_be_positive(self) -> None:
        self.write_log()
        self.assertEqual(self.mix("--days", "0").code, 2)


if __name__ == "__main__":
    unittest.main()
