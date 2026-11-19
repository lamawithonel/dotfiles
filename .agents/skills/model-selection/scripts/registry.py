#!/usr/bin/env python3
"""Shared helpers for the v4 model-selection registry: load, band, and cost.

`score.py`, `refresh-benchmarks.py`, and the migration all import this
module, so a band or a repriced cost means the same thing everywhere.
Registry JSON is untyped at this boundary, hence the `Any` mappings.
"""

import json
import re
from collections.abc import Iterable, Mapping
from typing import Any, Final

SCHEMA_VERSION: Final = 4
EFFORTS: Final = ("off", "minimal", "low", "medium", "high", "xhigh", "max", "single")

type Json = Mapping[str, Any]


class RegistryError(Exception):
    """The registry file is missing, unreadable, or not schema v4."""


def load(path: str) -> dict[str, Any]:
    """Read a v4 registry; refuse any other schema version."""
    try:
        with open(path, encoding="utf-8") as f:
            reg = json.load(f)
    except (OSError, json.JSONDecodeError) as err:
        raise RegistryError(f"cannot read registry {path}: {err}") from err
    if reg.get("schema_version") != SCHEMA_VERSION:
        raise RegistryError(
            f"registry {path} is schema {reg.get('schema_version')!r}, "
            f"need {SCHEMA_VERSION}"
        )
    return reg


def canonical_id(model_id: str) -> str:
    """Fold spellings of one model to a key: case, `.` vs `-`, and suffixes.

    Pi, OpenRouter, and Claude Code name the same model differently
    (`claude-fable-5.1`, `claude-fable-5-1[1m]`, `gpt-6-astra:free`), and a
    mythos model must stay mythos under every name.
    """
    base = re.sub(r"\[[^\]]*\]$|:[^/]*$", "", model_id.strip().lower())
    return base.replace(".", "-")


def is_mythos(model_id: str, entries: Iterable[str]) -> bool:
    """Whether a policy `mythos` entry names the model.

    An entry is an exact ID, or a family that ends in `*`
    (`anthropic/claude-fable-*`): the family covers every later version
    with no edit to the policy.
    """
    have = canonical_id(model_id)
    for entry in entries:
        want = canonical_id(entry)
        if want.endswith("*"):
            if have.startswith(want[:-1]):
                return True
        elif have == want:
            return True
    return False


def band_of(aai: float | None, model_id: str, policy: Json) -> str | None:
    """Band for one variant: mythos by name, else the highest floor met."""
    bands = policy["bands"]
    if is_mythos(model_id, bands["mythos"]):
        return "mythos"
    if aai is None:
        return None
    met = None
    for name in bands["order"]:
        floor = bands["floors"].get(name)
        if floor is not None and aai >= floor:
            met = name
    return met


def effective_aai(
    reg: Json, model_id: str, effort: str
) -> tuple[float | None, str | None, str | None]:
    """Return (aai, confidence, source) for a variant.

    A measured AA value always wins over a hand-owned placement.
    """
    variant = reg["models"].get(model_id, {}).get("variants", {}).get(effort, {})
    if variant.get("aai") is not None:
        return variant["aai"], "high", "aa_free"
    placement = (
        reg.get("overrides", {}).get(model_id, {}).get("placements", {}).get(effort)
    )
    if placement and placement.get("aai") is not None:
        return placement["aai"], placement.get("confidence", "low"), "placement"
    return None, None, None


def blended(price: Json | None, policy: Json) -> float | None:
    """Blend input and output USD per 1M tokens with the policy weights."""
    if not price:
        return None
    inp, out = price.get("input"), price.get("output")
    if inp is None or out is None:
        return None
    weights = policy["cost"]["blend"]
    return weights["input"] * inp + weights["output"] * out


def repriced_cost(
    index_cost: float | None,
    channel_price: Json | None,
    aa_price: Json | None,
    policy: Json,
) -> float | None:
    """AA's index cost repriced from AA's price to the channel's price."""
    if index_cost is None:
        return None
    at_channel = blended(channel_price, policy)
    at_aa = blended(aa_price, policy)
    if at_channel is None or not at_aa:
        return None
    return index_cost * at_channel / at_aa


def vendor_of(reg: Json, model_id: str) -> str:
    """Vendor family for refusal re-routes: override, model, then ID prefix."""
    return (
        reg.get("overrides", {}).get(model_id, {}).get("vendor")
        or reg["models"].get(model_id, {}).get("vendor")
        or model_id.split("/", 1)[0]
    )


def _price_errors(where: str, price: Any) -> list[str]:
    if not isinstance(price, Mapping):
        return []
    return [
        f"{where}: negative price {k}={v}"
        for k, v in price.items()
        if k in ("input", "output") and isinstance(v, int | float) and v < 0
    ]


PAGE_KEYS: Final = frozenset(
    ("tb4", "lcr", "aa_cyber", "healthbench", "aa_3d", "omniscience", "factuality")
)
DOMAIN_KEYS: Final = frozenset(
    ("business", "health_med", "fin_acct", "strat_ops", "legal", "economics")
)
BOARD_KEYS: Final = frozenset(("score", "ci", "effort", "votes", "as_of"))


def _unknown_keys(where: str, obj: Any, allowed: frozenset[str]) -> list[str]:
    if not isinstance(obj, Mapping):
        return []
    return [f"{where}: unknown key {k!r}" for k in obj if k not in allowed]


def _variant_errors(reg: Json, order: list[str]) -> list[str]:
    errs: list[str] = []
    for mid, model in reg.get("models", {}).items():
        errs += _price_errors(f"models.{mid}.pricing", model.get("pricing"))
        errs += _price_errors(f"models.{mid}.aa_pricing", model.get("aa_pricing"))
        for effort, variant in model.get("variants", {}).items():
            if effort not in EFFORTS:
                errs.append(f"models.{mid}.variants: effort {effort!r} not in EFFORTS")
            band = variant.get("band")
            if band is not None and band not in order:
                errs.append(f"models.{mid}.variants.{effort}: unknown band {band!r}")
            where = f"models.{mid}.variants.{effort}"
            errs += _unknown_keys(f"{where}.page", variant.get("page"), PAGE_KEYS)
            errs += _unknown_keys(
                f"{where}.domains", variant.get("domains"), DOMAIN_KEYS
            )
        for board, entry in (model.get("boards") or {}).items():
            errs += _unknown_keys(f"models.{mid}.boards.{board}", entry, BOARD_KEYS)
    return errs


def _override_errors(reg: Json) -> list[str]:
    errs: list[str] = []
    for mid, ov in reg.get("overrides", {}).items():
        for key in ("placements", "pi_thinking"):
            for effort in ov.get(key, {}):
                if effort not in EFFORTS:
                    errs.append(
                        f"overrides.{mid}.{key}: effort {effort!r} not in EFFORTS"
                    )
    return errs


def _host_errors(reg: Json) -> list[str]:
    errs: list[str] = []
    for host, h in reg.get("hosts", {}).items():
        for mid, entry in h.get("roster", {}).items():
            errs += _price_errors(
                f"hosts.{host}.roster.{mid}.price", entry.get("price")
            )
            for lvl in entry.get("pi_levels", []):
                if lvl not in EFFORTS:
                    errs.append(
                        f"hosts.{host}.roster.{mid}: pi level {lvl!r} not in EFFORTS"
                    )
    return errs


def validate(reg: Json) -> list[str]:
    """Return every structural problem in a v4 registry (empty means valid)."""
    if reg.get("schema_version") != SCHEMA_VERSION:
        return [
            f"schema_version is {reg.get('schema_version')!r}, need {SCHEMA_VERSION}"
        ]
    policy = reg.get("policy")
    if not isinstance(policy, Mapping):
        return ["policy block is missing"]
    order = policy.get("bands", {}).get("order")
    if not isinstance(order, list) or not order:
        return ["policy.bands.order is missing"]
    return _variant_errors(reg, order) + _override_errors(reg) + _host_errors(reg)
