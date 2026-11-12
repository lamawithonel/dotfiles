#!/usr/bin/env python3
"""Pick the best model for a band, tag, and profile from the v4 registry.

    score.py --pick [--band B | --role R] [--tag T] [--lang L]
             [--profile P] [--effort E] [--host H] [--registry F] [--today D]
    score.py --table [--profile P]

`--pick` prints one JSON object.  Exit codes: 0 with a pick or a degrade, 3
with neither (the JSON still prints), 2 on usage or registry errors.
Registry JSON is untyped at this boundary, hence the `Any` mappings.
"""

import argparse
import json
import math
import os
import shlex
import socket
import statistics
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime, timedelta
from typing import Any, Final, NoReturn

# Local imports must not leave __pycache__ in scripts/: the skill
# validator requires every file there to be executable.
sys.dont_write_bytecode = True

import registry

type Reg = Mapping[str, Any]

CORE_SOURCES: Final = ("aa_free", "openrouter", "pi_roster", "claude_roster")
# Boards whose feed is named differently from the board key.
BOARD_SOURCE: Final = {
    "aa_3d": "aa_page_3d",
    "aa_cyber": "aa_page_cyber",
    "tb4": "aa_page_lcr",
    "healthbench": "aa_page_healthbench",
    "health_med": "aa_free",
    "business": "aa_free",
}

# A tag may not move a pick to a variant costing more than this multiple of
# the untagged pick.  Code, not registry policy: `swap.sh update` never
# writes policy, so a registry key would never reach the live file.
TAG_COST_CEILING: Final = 1.5
DEFAULT_REGISTRY: Final = os.path.expanduser("~/.agents/model-benchmarks.json")
RETIRED_PROFILES: Final = frozenset({"coding", "reasoning", "style"})
# Hierarchy v2 has one coordinator class; registries from v1 still list "lead".
RETIRED_ROLES: Final = frozenset({"lead", "subdomain", "subdomain-coordinator"})
NEW_INTERFACE: Final = "use --pick --band bulk|haiku|sonnet|opus [--tag T] [--lang L]"
DEFAULT_PAYLOAD: Final = "payload.md"
DEV_NULL: Final = "< /dev/null"


class UsageError(Exception):
    """Bad command line, unknown name, or unusable registry content."""


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise UsageError(message)


@dataclass(frozen=True, slots=True)
class Request:
    band: str | None
    role: str | None
    tag: str | None
    lang: str | None
    effort: str | None
    model: str | None


@dataclass(frozen=True, slots=True)
class Ctx:
    reg: Reg
    policy: Reg
    host_name: str
    host: Reg
    profile_name: str
    profile_source: str
    profile: Reg
    env: Mapping[str, str]
    today: date
    warnings: list[str]
    payload: str
    aged: Mapping[str, date]


@dataclass(frozen=True, slots=True)
class Variant:
    model_id: str
    effort: str
    harness: str
    band: str | None
    aai: float
    confidence: str
    subscription: bool
    cost: float | None
    index_cost: float | None
    entry: Reg
    estimated: bool = False

    @property
    def value(self) -> float | None:
        return self.aai / self.cost if self.cost else None


@dataclass(frozen=True, slots=True)
class Selection:
    band: str | None
    pick: Variant | None
    degrade: Variant | None
    pool: Sequence[Variant]


# --- arguments ---------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    p = _Parser(prog="score.py", description="Pick a model for a band.")
    p.add_argument("--pick", action="store_true")
    p.add_argument("--table", action="store_true")
    p.add_argument("--mix", action="store_true")
    p.add_argument("--session")
    p.add_argument("--days", type=int, default=7)
    p.add_argument("--log")
    for name in ("band", "role", "tag", "lang", "model"):
        p.add_argument(f"--{name}")
    p.add_argument("--effort", choices=[e for e in registry.EFFORTS if e != "single"])
    for name in ("profile", "host", "registry", "today"):
        p.add_argument(f"--{name}")
    p.add_argument("--payload", default=DEFAULT_PAYLOAD)
    p.add_argument("--system")
    p.add_argument("--tier")
    return p


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    ns = build_parser().parse_args(argv)
    if ns.system is not None:
        raise UsageError(f"--system is retired; {NEW_INTERFACE}")
    if ns.tier is not None:
        raise UsageError(f"--tier is retired; {NEW_INTERFACE}")
    if ns.role in RETIRED_ROLES:
        raise UsageError(
            f"--role {ns.role} is retired; use --role coordinator "
            "(one coordinator class, see ~/.agents/ROLES.md)"
        )
    if ns.profile in RETIRED_PROFILES:
        raise UsageError(f"--profile {ns.profile} is retired; {NEW_INTERFACE}")
    if ns.days < 1:
        raise UsageError(f"--days needs a positive count, got {ns.days}")
    return ns


def parse_today(text: str | None) -> date:
    if text is None:
        return date.today()
    try:
        return date.fromisoformat(text)
    except ValueError as err:
        raise UsageError(f"--today needs YYYY-MM-DD, got {text!r}") from err


# --- context -----------------------------------------------------------


def detect_profile(
    flag: str | None, env: Mapping[str, str], host: Reg
) -> tuple[str, str]:
    """First hit wins: flag, env override, Pi, Bedrock, Claude Code, host.

    The innermost harness wins: Pi started from Claude Code inherits both
    markers, so the Pi markers are tested before CLAUDECODE.
    """
    if flag:
        return flag, "--profile"
    if env.get("MODEL_ROUTER_PROFILE"):
        return env["MODEL_ROUTER_PROFILE"], "MODEL_ROUTER_PROFILE"
    if env.get("MODEL_ROUTER_HARNESS") == "pi":
        return "pi-zdr", "MODEL_ROUTER_HARNESS"
    if env.get("PI_CODING_AGENT"):
        return "pi-zdr", "PI_CODING_AGENT"
    if env.get("CLAUDE_CODE_USE_BEDROCK") == "1":
        return "claude-code-bedrock", "CLAUDE_CODE_USE_BEDROCK"
    if env.get("CLAUDECODE"):
        return "claude-code", "CLAUDECODE"
    return host["default_profile"], "host default_profile"


def select_host(reg: Reg, name: str, warnings: list[str]) -> Reg:
    hosts = reg["hosts"]
    if name in hosts:
        return hosts[name]
    if "*" not in hosts:
        raise UsageError(f"unknown host {name} and the registry has no '*' host")
    warnings.append(f"unknown host {name}; using the '*' fallback host")
    return hosts["*"]


def _parse_day(text: str | None) -> date | None:
    try:
        return date.fromisoformat(text[:10]) if text else None
    except ValueError:
        return None


def relevant_sources(policy: Reg, ns: argparse.Namespace) -> set[str]:
    """Core feeds plus the feeds behind the requested tag, language, or role."""
    tags = [ns.tag, ns.lang]
    if ns.role:
        tags.append(policy.get("roles", {}).get(ns.role, {}).get("rank_on"))
    out: set[str] = set(CORE_SOURCES)
    for tag in filter(None, tags):
        spec = policy["tags"].get(tag, {})
        for board in filter(None, (spec.get("board"), spec.get("tiebreak"))):
            out.add(BOARD_SOURCE.get(str(board), str(board)))
    return out


def source_warnings(reg: Reg, today: date, only: set[str]) -> list[str]:
    stale_days = reg["policy"].get("stale_days", 14)
    out: list[str] = []
    for name, src in reg.get("sources", {}).items():
        if name not in only:
            continue
        status = src.get("status")
        if status in ("failed", "stale"):
            out.append(f"source {name} is {status}")
            continue
        seen = _parse_day(src.get("as_of"))
        if status != "retired" and seen and (today - seen).days > stale_days:
            out.append(f"source {name} is stale (as of {seen})")
    return out


def store_warnings(ctx_host: Reg, profile: Reg, policy: Reg, today: date) -> list[str]:
    store = ctx_host.get("pi_models_store")
    if "pi" not in profile["harnesses"] or not store:
        return []
    try:
        raw = store["checked_at"].replace("Z", "+00:00")
        checked = datetime.fromisoformat(raw).astimezone(UTC).date()
    except (KeyError, ValueError):
        return ["pi_models_store has no usable checked_at"]
    limit = policy.get("models_store_stale_days", 7)
    if (today - checked).days > limit:
        return [f"pi_models_store is stale (checked {checked})"]
    return []


def aged_sources(reg: Reg, today: date) -> dict[str, date]:
    """Sources whose `as_of` is older than `policy.age_out_days`."""
    limit = reg["policy"].get("age_out_days")
    out: dict[str, date] = {}
    if limit is None:
        return out
    for name, src in reg.get("sources", {}).items():
        seen = _parse_day(src.get("as_of"))
        if seen and (today - seen).days > limit:
            out[name] = seen
    return out


def is_aged(ctx: Ctx, source: str) -> bool:
    """True when the source is aged out; warns once per source."""
    seen = ctx.aged.get(source)
    if seen is None:
        return False
    days = ctx.policy.get("age_out_days")
    ctx.warnings.append(
        f"source {source} is older than {days} days (as of {seen}); "
        "its values are ignored"
    )
    return True


def make_ctx(ns: argparse.Namespace, env: Mapping[str, str]) -> Ctx:
    path = ns.registry or env.get("MODEL_BENCHMARKS", DEFAULT_REGISTRY)
    reg = registry.load(path)
    problems = registry.validate(reg)
    if problems:
        extra = f" (+{len(problems) - 1} more)" if len(problems) > 1 else ""
        raise UsageError(f"invalid registry {path}: {problems[0]}{extra}")
    today = parse_today(ns.today)
    warnings = source_warnings(reg, today, relevant_sources(reg["policy"], ns))
    name = ns.host or env.get("MODEL_ROUTER_HOST") or socket.gethostname().split(".")[0]
    host = select_host(reg, name, warnings)
    pname, source = detect_profile(ns.profile, env, host)
    profile = reg["policy"]["profiles"].get(pname)
    if profile is None:
        raise UsageError(f"unknown profile {pname!r}")
    if profile.get("placeholder"):
        warnings.append(f"profile {pname} is a placeholder")
    warnings += store_warnings(host, profile, reg["policy"], today)
    aged = aged_sources(reg, today)
    return Ctx(
        reg,
        reg["policy"],
        name,
        host,
        pname,
        source,
        profile,
        env,
        today,
        warnings,
        ns.payload,
        aged,
    )


# --- candidates --------------------------------------------------------


def _thinking_level(ctx: Ctx, model_id: str, effort: str, entry: Reg) -> str:
    """The Pi --thinking level for a variant.

    AA scores a single-variant model at its provider default, so send
    `high`, the middle level every mapped reasoning model lists, rather
    than the costliest one.  Without `high`, use the top listed level.
    """
    over = ctx.reg.get("overrides", {}).get(model_id, {}).get("pi_thinking", {})
    if effort in over:
        return over[effort]
    if effort != "single":
        return effort
    levels = [x for x in registry.EFFORTS if x in entry.get("pi_levels", [])]
    return "high" if "high" in levels or not levels else levels[-1]


def _cost(ctx: Ctx, model_id: str, entry: Reg, billing: str, ic: float | None):
    if billing == "subscription":
        return 0.0
    model = ctx.reg["models"].get(model_id, {})
    price = entry.get("price") or model.get("pricing")
    return registry.repriced_cost(ic, price, model.get("aa_pricing"), ctx.policy)


def aai_of(ctx: Ctx, model_id: str, effort: str) -> tuple[float | None, str | None]:
    """Effective AAI and confidence; a measured value from an aged source is dropped."""
    aai, conf, src = registry.effective_aai(ctx.reg, model_id, effort)
    if src != "aa_free" or not is_aged(ctx, "aa_free"):
        return aai, conf
    placed = ctx.reg.get("overrides", {}).get(model_id, {}).get("placements", {})
    spot = placed.get(effort)
    if spot and spot.get("aai") is not None:
        return spot["aai"], spot.get("confidence", "low")
    return None, None


def _blended_price(ctx: Ctx, model: Reg) -> float | None:
    return registry.blended(model.get("aa_pricing"), ctx.policy) or registry.blended(
        model.get("pricing"), ctx.policy
    )


def _tokens(ctx: Ctx, model: Reg, effort: str) -> float | None:
    """Tokens AA spent running its index: index cost over the blended price."""
    ic = model.get("variants", {}).get(effort, {}).get("index_cost_usd")
    price = _blended_price(ctx, model)
    return None if ic is None or not price else ic / price


def _scaled_tokens(ctx: Ctx, model: Reg, effort: str) -> float | None:
    """The model's nearest measured effort, scaled by the median effort ratio."""
    measured = [e for e in model.get("variants", {}) if _tokens(ctx, model, e)]
    if not measured:
        return None
    pos = registry.EFFORTS.index
    ref = min(measured, key=lambda e: (abs(pos(e) - pos(effort)), pos(e)))
    ratios: list[float] = []
    for other in ctx.reg["models"].values():
        num, den = _tokens(ctx, other, effort), _tokens(ctx, other, ref)
        if num is not None and den:
            ratios.append(num / den)
    base = _tokens(ctx, model, ref)
    return base * statistics.median(ratios) if base and ratios else None


def estimate_index_cost(ctx: Ctx, model_id: str, effort: str) -> float | None:
    """Estimate a missing index cost, or None when nothing supports one."""
    model = ctx.reg["models"].get(model_id, {})
    price = _blended_price(ctx, model)
    if not price:
        return None
    tokens = _scaled_tokens(ctx, model, effort)
    if tokens is None:
        seen = [_tokens(ctx, m, effort) for m in ctx.reg["models"].values()]
        known = [x for x in seen if x is not None]
        tokens = statistics.median(known) if known else None
    return None if tokens is None else tokens * price


def make_variant(
    ctx: Ctx, model_id: str, entry: Reg, effort: str, harness: str, hcfg: Reg
) -> Variant | None:
    aai, conf = aai_of(ctx, model_id, effort)
    if aai is None:
        return None
    if harness == "pi":
        level = _thinking_level(ctx, model_id, effort, entry)
        levels = entry.get("pi_levels")
        if levels and level not in levels:
            ctx.warnings.append(
                f"skipped {model_id} {effort}: pi level {level!r} not in pi_levels"
            )
            return None
    billing = hcfg.get("billing", "metered")
    model = ctx.reg["models"].get(model_id, {})
    ic = model.get("variants", {}).get(effort, {}).get("index_cost_usd")
    guess = None
    if billing == "subscription" and ic is None:
        guess = estimate_index_cost(ctx, model_id, effort)
    return Variant(
        model_id,
        effort,
        harness,
        registry.band_of(aai, model_id, ctx.policy),
        aai,
        conf or "low",
        billing == "subscription",
        _cost(ctx, model_id, entry, billing, ic),
        ic if guess is None else guess,
        entry,
        guess is not None,
    )


def _efforts(ctx: Ctx, model_id: str) -> list[str]:
    own = ctx.reg["models"].get(model_id, {}).get("variants", {})
    placed = ctx.reg.get("overrides", {}).get(model_id, {}).get("placements", {})
    return sorted(set(own) | set(placed))


def _entry_in_scope(
    ctx: Ctx, model_id: str, entry: Reg, harness: str, hcfg: Reg
) -> bool:
    if entry.get("harness") != harness or not entry.get("enabled", True):
        return False
    if ctx.reg.get("overrides", {}).get(model_id, {}).get("track_only"):
        return False
    roster = hcfg.get("roster")
    return roster is None or roster in entry.get("rosters", [])


def _usable_harnesses(ctx: Ctx) -> list[tuple[str, Reg]]:
    out: list[tuple[str, Reg]] = []
    for name, hcfg in ctx.profile["harnesses"].items():
        state = ctx.host.get("harnesses", {}).get(name)
        if state is None:
            continue
        if not state.get("healthy", False):
            ctx.warnings.append(f"harness {name} is unhealthy on {ctx.host_name}")
            continue
        out.append((name, hcfg))
    return out


def build_candidates(ctx: Ctx, include_mythos: bool) -> list[Variant]:
    """Every variant the profile may dispatch; mythos only when asked."""
    out: list[Variant] = []
    for harness, hcfg in _usable_harnesses(ctx):
        for model_id, entry in ctx.host.get("roster", {}).items():
            if not _entry_in_scope(ctx, model_id, entry, harness, hcfg):
                continue
            for effort in _efforts(ctx, model_id):
                var = make_variant(ctx, model_id, entry, effort, harness, hcfg)
                if var and (include_mythos or var.band != "mythos"):
                    out.append(var)
    return out


# --- ranking and tags --------------------------------------------------


def rank_key(v: Variant) -> tuple[Any, ...]:
    """Subscription first (cheapest index cost), then value (free metered ahead), then AAI."""
    tail = (v.model_id, v.effort)
    if v.subscription:
        ic = math.inf if v.index_cost is None else v.index_cost
        return (0, ic, -v.aai, *tail)
    if v.cost == 0:
        return (1, -math.inf, -v.aai, *tail)
    if v.value is not None:
        return (1, -v.value, -v.aai, *tail)
    return (2, 0, -v.aai, *tail)


def board_score(ctx: Ctx, v: Variant, board: str) -> tuple[float, float] | None:
    model = ctx.reg["models"].get(v.model_id, {})
    if is_aged(ctx, BOARD_SOURCE.get(board, board)):
        return None
    entry = model.get("boards", {}).get(board)
    if entry and entry.get("score") is not None:
        return entry["score"], entry.get("ci") or 0.0
    var = model.get("variants", {}).get(v.effort, {})
    for group in ("domains", "page"):
        val = var.get(group, {}).get(board)
        if val is not None:
            return val, 0.0
    return None


def _within(margin: Any, best: tuple[float, float], cur: tuple[float, float]) -> bool:
    if margin == "ci":
        return abs(best[0] - cur[0]) <= best[1] + cur[1]
    return cur[0] >= best[0] - margin


def _tie_key(ctx: Ctx, tiebreak: str | None):
    """Rank key where equal values fall to the higher tiebreak-board score."""

    def key(v: Variant) -> tuple[Any, ...]:
        base = rank_key(v)
        if tiebreak is None:
            return base
        got = board_score(ctx, v, tiebreak)
        return (*base[:2], -(got[0] if got else -math.inf), *base[2:])

    return key


def narrow(ctx: Ctx, cands: Sequence[Variant], tag: str) -> list[Variant]:
    """Keep the variants competitive on the tag's board, in rank order.

    Among equal values the higher score on the tag's `tiebreak` board wins.
    """
    spec = ctx.policy["tags"][tag]
    ranked = sorted(cands, key=_tie_key(ctx, spec.get("tiebreak")))
    if not ranked:
        return ranked
    if board_score(ctx, ranked[0], spec["board"]) is None:
        ctx.warnings.append(
            f"tag {tag} has no score for {ranked[0].model_id}; not routing away"
        )
        return ranked
    scored = [
        (v, s) for v in ranked if (s := board_score(ctx, v, spec["board"])) is not None
    ]
    best = max((s for _, s in scored), key=lambda s: s[0])
    return [v for v, s in scored if _within(spec["margin"], best, s)]


def tag_cost(v: Variant) -> float | None:
    """Cost for the tag ceiling: AA index cost on a plan, else the channel cost."""
    return v.index_cost if v.subscription else v.cost


def estimate_warning(v: Variant) -> str:
    cost = v.index_cost or 0.0
    return f"index cost of {v.model_id} at {v.effort} is estimated (${cost:,.0f})"


def cap_pool(ctx: Ctx, ranked: list[Variant]) -> list[Variant]:
    """Drop variants costing over the ceiling times the untagged pick's cost."""
    base = ranked[0]
    limit = tag_cost(base)
    if limit is None:
        ctx.warnings.append(
            f"untagged pick {base.model_id} at {base.effort} has no cost; "
            "tag cost ceiling not applied"
        )
        return ranked
    if base.estimated:
        ctx.warnings.append(estimate_warning(base))
    limit *= TAG_COST_CEILING
    return [v for v in ranked if (c := tag_cost(v)) is not None and c <= limit]


def cap_warning(tag: str, v: Variant, base: Variant) -> str:
    cost, floor = tag_cost(v), tag_cost(base)
    if cost is None:
        how = "at an unknown cost"
    elif not floor:
        how = f"at ${cost:,.0f} against a free untagged pick"
    else:
        how = f"at {cost / floor:.1f}x the untagged pick's cost"
    note = " (estimated cost)" if v.estimated or base.estimated else ""
    return (
        f"tag {tag} would pick {v.model_id} {v.effort} {how}; "
        f"capped at {TAG_COST_CEILING:g}x{note}"
    )


def narrow_all(ctx: Ctx, pool: Sequence[Variant], tags: Sequence[str]) -> list[Variant]:
    """Cap by cost, then narrow on each tag; warn when the cap changed the head."""
    ranked = sorted(pool, key=rank_key)
    if not (ranked and tags):
        return ranked
    base, free, probe = ranked[0], ranked, replace(ctx, warnings=[])
    ranked = cap_pool(ctx, ranked)
    first: tuple[str, Variant] | None = None
    for tag in tags:
        ranked = narrow(ctx, ranked, tag)
        free = narrow(probe, free, tag)  # uncapped comparison; its warnings are dropped
        if first is None and free[0] is not ranked[0]:
            first = (tag, free[0])
    if first and free[0] is not ranked[0]:
        ctx.warnings.append(cap_warning(first[0], first[1], base))
    return ranked


# --- selection ---------------------------------------------------------


def _band_order(ctx: Ctx) -> list[str]:
    return [b for b in ctx.policy["bands"]["order"] if b != "mythos"]


def step_up(
    ctx: Ctx, cands: Sequence[Variant], band: str
) -> tuple[str, list[Variant]] | None:
    order = _band_order(ctx)
    for b in order[order.index(band) :]:
        pool = [v for v in cands if v.band == b]
        if pool:
            if b != band:
                ctx.warnings.append(f"band {band} empty; stepped up to {b}")
            return b, pool
    return None


def find_degrade(
    ctx: Ctx, cands: Sequence[Variant], band: str, tags: Sequence[str]
) -> Selection | None:
    order = _band_order(ctx)
    for b in reversed(order[: order.index(band)]):
        pool = [v for v in cands if v.band == b]
        if pool:
            best = narrow_all(ctx, pool, tags)[0]
            ctx.warnings.append(
                f"band {band} empty; no {band}-band model in profile "
                f"{ctx.profile_name}; degrade to {best.model_id} "
                f"at {best.effort}"
            )
            return Selection(b, None, best, pool)
    return None


def select(
    ctx: Ctx, cands: Sequence[Variant], band: str, tags: Sequence[str]
) -> Selection:
    found = step_up(ctx, cands, band)
    if found:
        resolved, pool = found
        return Selection(resolved, narrow_all(ctx, pool, tags)[0], None, pool)
    if ctx.profile.get("empty_band") == "degrade":
        degraded = find_degrade(ctx, cands, band, tags)
        if degraded:
            return degraded
    ctx.warnings.append(f"no {band}-band or higher model in profile {ctx.profile_name}")
    return Selection(None, None, None, [])


def directive(
    ctx: Ctx, cands: Sequence[Variant], model_id: str, band: str
) -> Selection:
    own = [v for v in cands if v.model_id == model_id]
    in_band = [v for v in own if v.band == band]
    chosen = sorted(in_band or own, key=rank_key)
    if not chosen:
        ctx.warnings.append(f"model {model_id} is not available in {ctx.profile_name}")
        return Selection(None, None, None, [])
    return Selection(chosen[0].band, chosen[0], None, chosen)


# --- output ------------------------------------------------------------


def primary_harness(ctx: Ctx) -> str:
    return ctx.profile["primary"]


def herdr_on(ctx: Ctx) -> bool:
    setting = ctx.host.get("herdr")
    if setting == "env":
        return ctx.env.get("HERDR_ENV") == "1"
    return bool(setting)


def channel_of(ctx: Ctx, v: Variant) -> str:
    if v.harness == primary_harness(ctx):
        return "agent" if v.harness == "claude-code" else "pi"
    return "herdr" if herdr_on(ctx) else "shell"


def dispatch_effort(ctx: Ctx, v: Variant, req: Request) -> str:
    """Effort to dispatch: the flag, else the role default for Claude Code.

    A role default may lower a Claude pick, but never raise it out of its
    band: that would spend a higher band's share of the mix unseen.  The
    top floor band has nowhere higher to go, since mythos is by name.
    """
    if req.effort:
        return req.effort
    if v.harness != "claude-code":
        return v.effort
    role = ctx.policy.get("roles", {}).get(req.role or "worker", {})
    wanted = role.get("effort", "medium")
    if registry.EFFORTS.index(wanted) <= registry.EFFORTS.index(v.effort):
        return wanted
    floors = ctx.policy["bands"]["floors"]
    top = max(floors, key=floors.__getitem__)
    aai, _ = aai_of(ctx, v.model_id, wanted)
    if v.band == top or registry.band_of(aai, v.model_id, ctx.policy) == v.band:
        return wanted
    ctx.warnings.append(
        f"effort {wanted} would lift {v.model_id} out of band {v.band}; "
        f"dispatching at {v.effort}"
    )
    return v.effort


def pi_command(ctx: Ctx, v: Variant, thinking: str) -> str:
    template = ctx.policy["harnesses"]["pi"]["command"]
    cmd = template.format(
        model_ref=shlex.quote(str(v.entry.get("model_ref"))),
        effort=shlex.quote(thinking),
        payload=shlex.quote(ctx.payload),
    )
    return cmd if cmd.rstrip().endswith(DEV_NULL) else f"{cmd.rstrip()} {DEV_NULL}"


def describe(ctx: Ctx, v: Variant, req: Request) -> dict[str, Any]:
    effort = dispatch_effort(ctx, v, req)
    if v.harness == "pi":
        effort = _thinking_level(ctx, v.model_id, effort, v.entry)
    return {
        "id": v.model_id,
        "harness": v.harness,
        "channel": channel_of(ctx, v),
        "model_ref": v.entry.get("model_ref"),
        "model_param": v.entry.get("model_param"),
        "banded_effort": v.effort,
        "effort": effort,
        "command": pi_command(ctx, v, effort) if v.harness == "pi" else None,
        "aai": v.aai,
        "cost_usd": v.cost,
        "value": v.value,
        "confidence": v.confidence,
    }


def best_fallback(ctx: Ctx, sel: Selection) -> Variant | None:
    if sel.pick is None or sel.pick.harness == primary_harness(ctx):
        return None
    own = [v for v in sel.pool if v.harness == primary_harness(ctx)]
    return min(own, key=rank_key) if own else None


def best_on_refusal(ctx: Ctx, sel: Selection, req: Request) -> Variant | None:
    spec = ctx.policy["tags"].get(req.tag or "", {})
    chosen = sel.pick or sel.degrade
    if chosen is None or not spec.get("refusal_reroute"):
        return None
    own = registry.vendor_of(ctx.reg, chosen.model_id)
    scored: list[tuple[float, Variant]] = []
    for v in sel.pool:
        vendor = registry.vendor_of(ctx.reg, v.model_id)
        sc = board_score(ctx, v, spec["board"])
        if vendor not in (own, "anthropic") and sc is not None:
            scored.append((sc[0], v))
    if not scored:
        return None
    return min(scored, key=lambda t: (-t[0], rank_key(t[1])))[1]


def alias_warning(ctx: Ctx, v: Variant) -> str | None:
    hcfg = ctx.profile["harnesses"].get(v.harness, {})
    param = v.entry.get("model_param")
    target = ctx.host.get("bedrock_aliases", {}).get(param)
    if hcfg.get("price_source") != "bedrock" or not target or target == v.model_id:
        return None
    order = ctx.policy["bands"]["order"]
    aais = [aai_of(ctx, target, e)[0] for e in _efforts(ctx, target)]
    top = max((a for a in aais if a is not None), default=None)
    tband = registry.band_of(top, target, ctx.policy)
    if tband is None or order.index(tband) < order.index(v.band or "bulk"):
        return f"bedrock alias {param} resolves to {target}, below class {v.band}"
    return None


def chosen_warnings(ctx: Ctx, v: Variant) -> list[str]:
    out: list[str] = []
    if v.confidence in ("low", "medium"):
        out.append(f"{v.confidence} confidence on {v.model_id} at {v.effort}")
    if v.estimated:
        out.append(estimate_warning(v))
    if not v.subscription and v.cost is None:
        out.append(f"{v.model_id} at {v.effort} has no index cost; ranked by AAI")
    alias = alias_warning(ctx, v)
    return out + ([alias] if alias else [])


def reason_for(v: Variant | None, band: str | None, tag: str | None) -> str:
    if v is None:
        return "no candidate"
    where = f"{band} band" + (f", tag {tag}" if tag else "")
    if v.subscription:
        return f"subscription-billed, cheapest index cost in {where}: AAI {v.aai}"
    if v.cost == 0:
        return f"free (cost 0) in {where}: AAI {v.aai}"
    if v.cost:
        return f"best value in {where}: AAI {v.aai} per ${v.cost:,.0f}"
    return f"highest AAI in {where}: AAI {v.aai}, no index cost"


def dedupe(items: Sequence[str]) -> list[str]:
    return list(dict.fromkeys(items))


def mix_band(v: Variant) -> str | None:
    """The band this dispatch counts toward in the mix: the pick's band.

    The mix is stated in requested bands; role efforts (workers at
    `medium`) were set knowing they measure lower on AAI.
    """
    return v.band


def render(ctx: Ctx, req: Request, band: str, sel: Selection) -> dict[str, Any]:
    chosen = sel.pick or sel.degrade
    fallback = best_fallback(ctx, sel)
    refusal = best_on_refusal(ctx, sel, req)
    if chosen:
        ctx.warnings.extend(chosen_warnings(ctx, chosen))
    return {
        "band": band,
        "tag": req.tag,
        "lang": req.lang,
        "role": req.role,
        "profile": ctx.profile_name,
        "profile_source": ctx.profile_source,
        "host": ctx.host_name,
        "pick": describe(ctx, sel.pick, req) if sel.pick else None,
        "degrade": describe(ctx, sel.degrade, req) if sel.degrade else None,
        "fallback": describe(ctx, fallback, req) if fallback else None,
        "on_refusal": describe(ctx, refusal, req) if refusal else None,
        "mix_band": mix_band(chosen) if chosen else None,
        "reason": reason_for(chosen, sel.band, req.tag),
        "warnings": dedupe(ctx.warnings),
    }


# --- commands ----------------------------------------------------------


def make_request(ctx: Ctx, ns: argparse.Namespace) -> tuple[Request, str, list[str]]:
    """Validate names; return the request, the band, and the tag chain."""
    roles = ctx.policy.get("roles", {})
    tags = ctx.policy["tags"]
    role = roles.get(ns.role) if ns.role else None
    if ns.role and role is None:
        raise UsageError(f"unknown role {ns.role!r}")
    checks = (
        (ns.tag, ("skill", "domain"), "specialty tag"),
        (ns.lang, ("language",), "language group"),
    )
    for name, kinds, label in checks:
        if name and tags.get(name, {}).get("kind") not in kinds:
            raise UsageError(f"unknown {label} {name!r}")
    band: str = ns.band or (role or {}).get("band") or ""
    if band not in ctx.policy["bands"]["order"]:
        raise UsageError("--pick needs --band bulk|haiku|sonnet|opus|mythos or --role")
    chain = [t for t in ((role or {}).get("rank_on"), ns.tag, ns.lang) if t]
    req = Request(ns.band, ns.role, ns.tag, ns.lang, ns.effort, ns.model)
    return req, band, dedupe(chain)


def pick_command(ctx: Ctx, ns: argparse.Namespace) -> int:
    req, band, chain = make_request(ctx, ns)
    cands = build_candidates(ctx, include_mythos=bool(req.model) or band == "mythos")
    if req.model:
        sel = directive(ctx, cands, req.model, band)
    elif band == "mythos":
        return mythos_listing(ctx, req, cands)
    else:
        sel = select(ctx, cands, band, chain)
    print(json.dumps(render(ctx, req, band, sel), indent=2))
    return 0 if (sel.pick or sel.degrade) else 3


def mythos_listing(ctx: Ctx, req: Request, cands: Sequence[Variant]) -> int:
    ctx.warnings.append("mythos is directive-only; name it with --model")
    ranked = sorted((v for v in cands if v.band == "mythos"), key=rank_key)
    out = render(ctx, req, "mythos", Selection("mythos", None, None, ranked))
    out["ranked"] = [describe(ctx, v, req) for v in ranked]
    print(json.dumps(out, indent=2))
    return 3


def table_command(ctx: Ctx) -> int:
    cands = build_candidates(ctx, include_mythos=True)
    req = Request(None, None, None, None, None, None)
    lines = [f"Profile {ctx.profile_name} on {ctx.host_name}", ""]
    for band in ctx.policy["bands"]["order"]:
        lines += [
            f"## {band}",
            "",
            "| # | model | effort | harness | AAI | cost | value |",
        ]
        lines.append("| - | - | - | - | - | - | - |")
        ranked = sorted((v for v in cands if v.band == band), key=rank_key)
        lines += [_row(i, describe(ctx, v, req)) for i, v in enumerate(ranked, 1)]
        lines.append("")
    print("\n".join(lines))
    return 0


def _row(rank: int, d: Mapping[str, Any]) -> str:
    cost = "-" if d["cost_usd"] is None else f"{d['cost_usd']:,.0f}"
    value = "-" if d["value"] is None else f"{d['value']:.4f}"
    return (
        f"| {rank} | {d['id']} | {d['banded_effort']} | {d['harness']} "
        f"| {d['aai']} | {cost} | {value} |"
    )


# --- measured mix ------------------------------------------------------


def dispatch_log(env: Mapping[str, str]) -> str:
    """The log the log-dispatch hook writes; keep in step with the hook."""
    if env.get("MODEL_ROUTER_DISPATCH_LOG"):
        return env["MODEL_ROUTER_DISPATCH_LOG"]
    state = env.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(state, "agents", "model-router", "dispatches.jsonl")


def read_dispatches(
    path: str, since: date, session: str | None
) -> tuple[list[Reg], int]:
    """Records dated after `since` (and in `session`), plus the bad-line count."""
    records: list[Reg] = []
    bad = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
                day = date.fromisoformat(rec["ts"][:10])
                str(rec["model"])
            except (ValueError, KeyError, TypeError):
                bad += 1
                continue
            if day > since and session in (None, rec.get("session_id")):
                records.append(rec)
    return records, bad


def _names_model(name: str | None, want: str) -> bool:
    if not name:
        return False
    have = registry.canonical_id(name)
    return have == want or have.endswith("/" + want)


def resolve_model(ctx: Ctx, model: str, harness: str | None) -> str | None:
    """The roster ID a logged model names, by ID, model_ref, or model_param."""
    want = registry.canonical_id(model)
    hits = [
        mid
        for mid, e in ctx.host["roster"].items()
        if (e.get("harness") == "pi") == (harness == "pi")
        and any(
            _names_model(n, want)
            for n in (mid, e.get("model_ref"), e.get("model_param"))
        )
    ]
    anchor = ctx.policy["bands"]["reference_effort"]
    # An alias such as "haiku" names every generation; it runs the newest,
    # which is the strongest at the anchor effort.
    return max(
        hits,
        key=lambda m: registry.effective_aai(ctx.reg, m, anchor)[0] or -1,
        default=None,
    )


def counted_effort(ctx: Ctx, model_id: str, harness: str | None, sent: Any) -> str:
    """max(effort sent, anchor); a Pi level maps back through pi_thinking."""
    order = [e for e in registry.EFFORTS if e != "single"]
    anchor = ctx.policy["bands"]["reference_effort"]
    if harness == "pi":
        over = ctx.reg.get("overrides", {}).get(model_id, {}).get("pi_thinking", {})
        back = [e for e, level in over.items() if level == sent and e in order]
        sent = max(back, key=order.index) if back else sent
    if sent not in order:
        return anchor
    return max(sent, anchor, key=order.index)


def counted_band(ctx: Ctx, model_id: str, effort: str) -> str | None:
    """Band at `effort`, else at `single`, else at the nearest lower variant."""
    order = [e for e in registry.EFFORTS if e != "single"]
    for e in (effort, "single", *reversed(order[: order.index(effort)])):
        aai = registry.effective_aai(ctx.reg, model_id, e)[0]
        if aai is not None:
            return registry.band_of(aai, model_id, ctx.policy)
    return registry.band_of(None, model_id, ctx.policy)


def mix_bands(order: Sequence[str], key: str) -> list[str]:
    """Bands a policy.mix key covers; mythos is directive-only and never in."""
    base = [b for b in order if b != "mythos"]
    if key.endswith("_or_below"):
        return base[: base.index(key.removesuffix("_or_below")) + 1]
    if key.endswith("_or_above"):
        return base[base.index(key.removesuffix("_or_above")) :]
    return [base[base.index(key)]]


def mix_report(ctx: Ctx, records: Sequence[Reg]) -> Reg:
    order = ctx.policy["bands"]["order"]
    bands = dict.fromkeys([*order, "unknown"], 0)
    unknown: list[str] = []
    for rec in records:
        mid = resolve_model(ctx, str(rec["model"]), rec.get("harness"))
        band = None
        if mid:
            band = counted_band(
                ctx,
                mid,
                counted_effort(ctx, mid, rec.get("harness"), rec.get("effort")),
            )
        if band is None:
            bands["unknown"] += 1
            unknown.append(str(rec["model"]))
        else:
            bands[band] += 1
    groups = {k: mix_bands(order, k) for k in ctx.policy["mix"]}
    basis = sum(bands[b] for g in groups.values() for b in g)
    mix: Reg = {}
    for key, target in ctx.policy["mix"].items():
        count = sum(bands[b] for b in groups[key])
        share = round(count / basis, 3) if basis else None
        dev = None if share is None else round(share - target, 3)
        mix[key] = {"count": count, "share": share, "target": target, "deviation": dev}
    return {
        "bands": bands,
        "basis": basis,
        "mix": mix,
        "unknown_models": dedupe(unknown),
    }


def mix_command(ctx: Ctx, ns: argparse.Namespace) -> int:
    path = ns.log or dispatch_log(ctx.env)
    if not os.path.exists(path):
        print(
            f"score.py: no dispatch log at {path}; the log-dispatch hook is not "
            "installed or has not run, so the mix is unmeasured",
            file=sys.stderr,
        )
        return 3
    since = ctx.today - timedelta(days=ns.days)
    records, bad = read_dispatches(path, since, ns.session)
    if bad:
        ctx.warnings.append(f"skipped {bad} unreadable line(s) in {path}")
    out = {
        "log": path,
        "days": ns.days,
        "session": ns.session,
        "host": ctx.host_name,
        "dispatches": len(records),
        **mix_report(ctx, records),
        "skipped_lines": bad,
        "warnings": dedupe(ctx.warnings),
    }
    print(json.dumps(out, indent=2))
    return 0


def run(argv: Sequence[str], env: Mapping[str, str]) -> int:
    ns = parse_args(argv)
    if not (ns.pick or ns.table or ns.mix):
        raise UsageError(f"nothing to do; {NEW_INTERFACE}, --table, or --mix")
    ctx = make_ctx(ns, env)
    if ns.mix:
        return mix_command(ctx, ns)
    return table_command(ctx) if ns.table else pick_command(ctx, ns)


def main(
    argv: Sequence[str] | None = None, env: Mapping[str, str] | None = None
) -> int:
    args = sys.argv[1:] if argv is None else argv
    try:
        return run(args, os.environ if env is None else env)
    except (UsageError, registry.RegistryError) as err:
        print(f"score.py: {err}", file=sys.stderr)
        return 2
    except (KeyError, TypeError, ValueError) as err:
        print(
            f"score.py: unusable registry content: {type(err).__name__}: {err}",
            file=sys.stderr,
        )
        return 2
    except SystemExit as err:
        return err.code if isinstance(err.code, int) else 0


if __name__ == "__main__":
    sys.exit(main())
