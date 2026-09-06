#!/usr/bin/env python3
"""Score and rank registry models per the model-router policy in SKILL.md.

Two tiering systems:

  general  profiles coding|reasoning|style; tiers 1-3 by quality Q and blended cost C,
           tier 4 = frontier (max Q, cost ignored, tier_4_only models eligible); a user
           directive naming a model still overrides every tier
  design   Design Arena ELO vs cost only; the Pareto frontier walked cost-ascending and
           spread over four rungs (1 = cheapest frontier point, 4 = best)

Policy constants live here and in SKILL.md only; the registry holds data.

Usage:
  score.py                         # every system/profile/tier, markdown tables
  score.py --profile coding --tier 2
  score.py --system design
  score.py --include-track-only    # also rank overrides.*.track_only models (comparison only)
  score.py --json
  score.py --pick --system general --profile coding --tier 2   # one winner + execution block
  score.py --pick --system design --tier 3
"""

import argparse
import datetime as dt
import json
import os
import socket
import sys

DEFAULT_REGISTRY = os.path.expanduser("~/.agents/model-benchmarks.json")
BENCH_FIELDS = (
    "aa_intelligence",
    "aa_coding",
    "aa_omniscience",
    "aa_factuality",
    "terminal_bench",
    "deep_swe",
    "eq_bench",
    "design_arena",
)
FEED_OF = {
    "aa_intelligence": "aa_api",
    "aa_coding": "aa_api",
    "terminal_bench": "aa_api",
    "aa_omniscience": "aa_omniscience",
    "aa_factuality": "aa_omniscience",
    "deep_swe": "deep_swe",
    "eq_bench": "eq_bench",
    "design_arena": "design_arena",
}

# --- policy constants (tunable policy, not data) ---
PROFILES = {
    "coding": {
        "aa_coding": 0.35,
        "deep_swe": 0.25,
        "terminal_bench": 0.15,
        "aa_omniscience": 0.15,
        "aa_factuality": 0.10,
    },
    "reasoning": {
        "aa_intelligence": 0.50,
        "aa_omniscience": 0.20,
        "aa_factuality": 0.15,
        "deep_swe": 0.15,
    },
    "style": {
        "design_arena": 0.45,
        "eq_bench": 0.25,
        "aa_factuality": 0.15,
        "aa_intelligence": 0.15,
    },
}
AGE_OUT_DAYS = 90  # a feed value not re-seen for this long scores as null
T1_FLOOR = 0.40  # Tier 1: eligible if Q >= floor, then min cost
T2_FLOOR = 0.60  # Tier 2: eligible if Q >= floor, then max V (cost alone must not pick a weak model)
EPS = 0.05  # Tier 2: V = Q / (C + EPS); host-compute floor for free models
T3_TIE = 0.02  # Tier 3: within this Q band prefer cheaper
MORE_BENCH_BAND = 0.05  # Q-direct comparisons: within this band prefer more benchmarks
STALE_WARN_DAYS = 14


class RegistryError(Exception):
    pass


def load(path):
    with open(path) as f:
        return json.load(f)


def blended_cost(pricing):
    p, c = pricing.get("prompt_cost_per_m"), pricing.get("completion_cost_per_m")
    if p is None or c is None:
        return None
    return 0.75 * p + 0.25 * c


def _days_between(a, b):
    return (dt.date.fromisoformat(b) - dt.date.fromisoformat(a)).days


def _tier4_only(reg, mid):
    return bool(
        (reg.get("overrides", {}).get(mid, {}).get("constraints") or {}).get(
            "tier_4_only"
        )
    )


def candidates(reg, host, today, include_track_only=False, include_tier4_only=False):
    """{id: {"model":..., "entry":..., "C":...}} eligible for automatic selection."""
    h = reg["hosts"].get(host)
    if not h:
        raise RegistryError(
            f"host {host!r} not in registry; run refresh-benchmarks.py on this host"
        )
    out = {}
    for mid, e in h["roster"].items():
        if e.get("is_class_entry") or not e.get("enabled"):
            continue
        if not all(h["channels"].get(hs) for hs in e.get("native_harness", [])):
            continue
        if not include_tier4_only and _tier4_only(reg, mid):
            continue
        m = reg["models"].get(mid)
        if not m:
            continue
        pricing = e.get("pricing") or m.get("pricing") or {}
        out[mid] = {
            "model": m,
            "entry": e,
            "C": blended_cost(pricing),
            "reg": reg,
            "today": today,
        }
    if include_track_only:
        for mid, m in reg["models"].items():
            if m.get("track_only") and mid not in out:
                if not include_tier4_only and _tier4_only(reg, mid):
                    continue
                out[mid] = {
                    "model": m,
                    "entry": {"track_only": True},
                    "C": blended_cost(m.get("pricing") or {}),
                    "reg": reg,
                    "today": today,
                }
    return out


def value(reg, m, field, today):
    """Benchmark value after comparability + age-out gates, else None."""
    v = m["benchmarks"].get(field)
    if v is None:
        return None
    feed = FEED_OF[field]
    pv = (reg.get("sources", {}).get(feed) or {}).get("primary_version")
    mv = (m.get("benchmark_versions") or {}).get(field)
    if pv and mv and mv != pv:
        return None
    seen = (m.get("last_seen") or {}).get(feed)
    if seen and _days_between(seen, today) > AGE_OUT_DAYS:
        return None
    return v


def normalized(cands, field):
    vals = {
        mid: value(c["reg"], c["model"], field, c["today"]) for mid, c in cands.items()
    }
    vals = {k: v for k, v in vals.items() if v is not None}
    if not vals:
        return {}
    lo, hi = min(vals.values()), max(vals.values())
    if hi == lo:
        return {k: 1.0 for k in vals}
    return {k: (v - lo) / (hi - lo) for k, v in vals.items()}


def quality(cands, weights):
    norms = {b: normalized(cands, b) for b in weights}
    out = {}
    for mid in cands:
        got = {b: norms[b][mid] for b in weights if mid in norms[b]}
        if not got:
            continue
        wsum = sum(weights[b] for b in got)
        out[mid] = {
            "Q": sum(weights[b] * got[b] for b in got) / wsum,
            "n": len(got),
            "norms": got,
        }
    return out


def _row(mid, cands, q):
    C = cands[mid]["C"]
    return {
        "id": mid,
        "Q": q[mid]["Q"],
        "n": q[mid]["n"],
        "C": C,
        "V": (q[mid]["Q"] / (C + EPS)) if C is not None else None,
        "norms": q[mid]["norms"],
        "track_only": bool(cands[mid]["entry"].get("track_only")),
    }


def rank_general(reg, host, today, weights, tier, include_track_only=False):
    cands = candidates(
        reg, host, today, include_track_only, include_tier4_only=(tier == 4)
    )
    q = quality(cands, weights)
    rows = [_row(mid, cands, q) for mid in q]
    if tier == 1:
        rows = [r for r in rows if r["Q"] >= T1_FLOOR and r["C"] is not None]
        rows.sort(key=lambda r: (r["C"], -r["Q"]))
    elif tier == 2:
        rows = [r for r in rows if r["V"] is not None and r["Q"] >= T2_FLOOR]
        rows.sort(key=lambda r: -r["V"])
    elif tier == 3:
        rows.sort(key=lambda r: -r["Q"])
        if len(rows) > 1:
            top, second = rows[0], rows[1]
            if (
                abs(top["Q"] - second["Q"]) <= T3_TIE
                and (second["C"] or 0) < (top["C"] or 0)
                or (
                    abs(top["Q"] - second["Q"]) <= MORE_BENCH_BAND
                    and second["n"] > top["n"]
                )
            ):
                rows[0], rows[1] = second, top
    elif tier == 4:
        # Frontier rung: quality only, cost ignored, tier_4_only models in play.
        rows.sort(key=lambda r: (-r["Q"], -r["n"], r["C"] if r["C"] is not None else 0))
        if len(rows) > 1:
            top, second = rows[0], rows[1]
            if (
                abs(top["Q"] - second["Q"]) <= MORE_BENCH_BAND
                and second["n"] > top["n"]
            ):
                rows[0], rows[1] = second, top
    else:
        raise ValueError("tier must be 1, 2, 3, or 4")
    return rows


def rank_design(reg, host, today, include_track_only=False):
    """Pareto frontier of (cost, design_arena) walked cost-ascending, spread over rungs 1..4."""
    cands = candidates(reg, host, today, include_track_only)
    pts = []
    for mid, c in cands.items():
        da = value(reg, c["model"], "design_arena", today)
        if da is None or c["C"] is None:
            continue
        pts.append(
            {
                "id": mid,
                "DA": da,
                "C": c["C"],
                "track_only": bool(c["entry"].get("track_only")),
            }
        )
    pts.sort(key=lambda p: (p["C"], -p["DA"]))
    frontier, best = [], float("-inf")
    for p in pts:
        if p["DA"] > best:
            frontier.append(p)
            best = p["DA"]
    ladder = {1: [], 2: [], 3: [], 4: []}
    n = len(frontier)
    for i, p in enumerate(frontier):
        rung = 1 if n == 1 else 1 + round(3 * i / (n - 1))
        ladder[rung].append(p)
    for rows in ladder.values():
        rows.sort(key=lambda p: -p["DA"])
    return ladder


# --- CLI ---------------------------------------------------------------------------------


def _fmt(x, nd=3):
    return "-" if x is None else f"{x:.{nd}f}"


def _table(rows, cols):
    head = "| " + " | ".join(c for c, _ in cols) + " |"
    sep = "|" + "|".join(" --- " for _ in cols) + "|"
    body = ["| " + " | ".join(f(r) for _, f in cols) + " |" for r in rows]
    return "\n".join([head, sep] + body)


def warn_stale(reg, today):
    for name, s in reg.get("sources", {}).items():
        if s.get("status") not in ("ok",):
            print(
                f"warn: source {name} status={s.get('status')} ({s.get('error')})",
                file=sys.stderr,
            )
        elif s.get("as_of") and _days_between(s["as_of"], today) > STALE_WARN_DAYS:
            print(
                f"warn: source {name} as_of {s['as_of']} older than {STALE_WARN_DAYS} days",
                file=sys.stderr,
            )


def pick(reg, host, today, system, profile, tier):
    """One winner with its dispatch block, for pasting into a brief.

    Design rungs and general tiers share the `tier` argument.  Returns
    a dict with `id` None when no model qualifies.
    """
    if system == "design":
        rows = rank_design(reg, host, today)[tier]
    else:
        rows = rank_general(reg, host, today, PROFILES[profile], tier)
    warnings = [
        f"{n}: {s.get('status')} ({s.get('error')})"
        for n, s in reg.get("sources", {}).items()
        if s.get("status") != "ok"
    ]
    if not rows:
        return {
            "system": system,
            "profile": profile,
            "tier": tier,
            "id": None,
            "warnings": warnings,
        }
    top = rows[0]
    entry = reg["hosts"][host]["roster"][top["id"]]
    return {
        "system": system,
        "profile": profile,
        "tier": tier,
        "id": top["id"],
        "Q": top.get("Q"),
        "DA": top.get("DA"),
        "C": top["C"],
        "context_window": entry.get("context_window"),
        "execution": entry["execution"],
        "runner_up": rows[1]["id"] if len(rows) > 1 else None,
        "warnings": warnings,
    }


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--registry", default=os.environ.get("MODEL_BENCHMARKS", DEFAULT_REGISTRY)
    )
    ap.add_argument(
        "--host",
        default=os.environ.get("MODEL_ROUTER_HOST", socket.gethostname().split(".")[0]),
    )
    ap.add_argument(
        "--today", default=dt.datetime.now(dt.timezone.utc).date().isoformat()
    )
    ap.add_argument("--system", choices=["general", "design", "all"], default="all")
    ap.add_argument("--profile", choices=list(PROFILES), default=None)
    ap.add_argument("--tier", type=int, choices=[1, 2, 3, 4], default=None)
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--include-track-only", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument(
        "--pick",
        action="store_true",
        help="print one winner with its execution block as JSON; needs --system and --tier (and --profile for general)",
    )
    a = ap.parse_args(argv)
    reg = load(a.registry)
    warn_stale(reg, a.today)
    if a.pick:
        if (
            a.system == "all"
            or a.tier is None
            or (a.system == "general" and not a.profile)
        ):
            ap.error(
                "--pick needs --system general --profile P --tier N, or --system design --tier N"
            )
        print(
            json.dumps(
                pick(reg, a.host, a.today, a.system, a.profile, a.tier), indent=2
            )
        )
        return 0
    out = {}
    if a.system in ("general", "all"):
        for prof in [a.profile] if a.profile else PROFILES:
            for tier in [a.tier] if a.tier else (1, 2, 3, 4):
                out[f"general/{prof}/tier{tier}"] = rank_general(
                    reg, a.host, a.today, PROFILES[prof], tier, a.include_track_only
                )[: a.top]
    if a.system in ("design", "all"):
        out["design"] = rank_design(reg, a.host, a.today, a.include_track_only)
    if a.json:
        print(json.dumps(out, indent=2))
        return 0
    for key, rows in out.items():
        if key == "design":
            print("\n### design ladder (Design Arena vs cost, Pareto frontier)\n")
            for rung in (4, 3, 2, 1):
                ids = (
                    ", ".join(
                        f"{p['id']} (DA {p['DA']:.0f}, C {p['C']:.2f}){' [track-only]' if p['track_only'] else ''}"
                        for p in rows[rung]
                    )
                    or "none"
                )
                print(f"- Tier {rung}: {ids}")
            continue
        print(f"\n### {key}\n")
        print(
            _table(
                rows,
                [
                    (
                        "model",
                        lambda r: (
                            r["id"] + (" [track-only]" if r["track_only"] else "")
                        ),
                    ),
                    ("Q", lambda r: _fmt(r["Q"])),
                    ("n", lambda r: str(r["n"])),
                    ("C $/M", lambda r: _fmt(r["C"], 3)),
                    ("V", lambda r: _fmt(r["V"], 2)),
                    (
                        "norms",
                        lambda r: " ".join(
                            f"{k}={v:.2f}" for k, v in r["norms"].items()
                        ),
                    ),
                ],
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
