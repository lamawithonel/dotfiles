#!/usr/bin/env python3
"""Sole writer of the model-selection registry (~/.agents/model-benchmarks.json), schema v4.

Phases, each independently failable (a failed fetch keeps old values):

  1. roster      Pi enabledModels + models-store, Claude candidates (probe)
  2. feeds       openrouter, aa_free, AA evaluation pages, Omniscience, boards
  3. overrides   hand-owned block shapes match keys, track-only models, placements
  4. derive      band and confidence per variant (registry.band_of)
  5. validate    registry.validate + hand-owned blocks unchanged
  6. write       atomic, one .bak generation, notify-send on change

Refresh reads `policy` and `overrides` and never writes them.  The AA free
API key is read from AA_API_KEY and sent only in the x-api-key header.  AA
evaluation pages are read once each and only the listed fields are kept.

Flags: --dry-run (print changes, no write), --probe (force Claude probe),
--no-probe, --skip FEED (repeatable), --registry PATH, --host NAME.

Prime directive: a number you did not fetch does not go in the file.
"""

import argparse
import copy
import json
import os
import random
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from collections.abc import Callable, Iterator, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from http.client import HTTPException, HTTPMessage
from typing import IO, Any, Final

# Local imports must not leave __pycache__ in scripts/: the skill
# validator requires every file there to be executable.
sys.dont_write_bytecode = True

import boards
import registry

type Reg = dict[str, Any]
type Cache = dict[str, list[boards.Row]]
type FeedFn = Callable[[Reg, Cache], "FeedResult"]

DEFAULT_REGISTRY: Final = os.path.expanduser("~/.agents/model-benchmarks.json")
PI_SETTINGS: Final = os.path.expanduser("~/.pi/agent/settings.json")
PI_STORE: Final = os.path.expanduser("~/.pi/agent/models-store.json")
CLAUDE_CACHE: Final = os.path.expanduser("~/.claude.json")
UA: Final = "Mozilla/5.0 (X11; Linux x86_64) model-selection/4"
TIMEOUT: Final = 45
KEY_SOURCE: Final = "openrouter-key"
# A price source only overwrites one of equal or lower rank; unlisted rank 0.
# The key's own price beats the list price, whichever feed runs last.
PRICE_RANK: Final[dict[str, int]] = {KEY_SOURCE: 2, "openrouter": 1}
ELO_DRIFT: Final = 10  # arena ELO recomputes ~2-hourly; damp churn below this
MAX_PAGES: Final = 12
BOARD_MAX_PAGES: Final = 150  # text/latest had 11,175 rows (112 pages) on 2026-11-10
PAGE_GAP: Final = 1.0  # seconds between pages; 0.25 drew HTTP 429 from datasets-server
FEED_WALL: Final = 600  # seconds a paged board feed may run before it fails
RETRY_BACKOFF: Final = (2, 4, 8)  # seconds before attempts 2, 3, and 4
RATE_BACKOFF: Final = (5, 10, 20, 40, 80)  # HTTP 429 without Retry-After, pre-jitter
RATE_JITTER: Final = (0.5, 1.5)  # each 429 backoff is multiplied by uniform(*this)
RETRY_AFTER_CAP: Final = 120  # seconds; a longer Retry-After with no deadline raises
PI_MIN_ENTRIES: Final = 5  # fewer OpenRouter entries in enabledModels is a bad read
PI_MIN_STORE: Final = 10  # fewer OpenRouter models in models-store is a bad read
REDACTED: Final = "***"
SEGMENT_CAP: Final = 60000  # bytes of one embedded model record we search
BUSINESS_PARTS: Final = ("fin_acct", "strat_ops", "legal", "economics")
PI_DEFAULT_LEVELS: Final = ["off", "minimal", "low", "medium", "high"]
THINKING: Final = ("off", "minimal", "low", "medium", "high", "xhigh", "max")
AA_SITE: Final = "https://artificialanalysis.ai"
AA_FREE_URL: Final = f"{AA_SITE}/api/v2/language/models/free"
OPENROUTER_URL: Final = "https://openrouter.ai/api/v1/models"
ARENA_DATASET_API: Final = (
    "https://huggingface.co/api/datasets/lmarena-ai/leaderboard-dataset"
)
HF_HOST: Final = "huggingface.co"
# Feed keys that differ from the ID-derived default (OpenRouter's real IDs).
MATCH_DEFAULTS: Final[dict[str, dict[str, str]]] = {
    "anthropic/claude-fable-5-1[1m]": {"openrouter": "anthropic/claude-fable-5.1"},
}
RETIRED: Final = {
    "aa_api": "retired: replaced by aa_free (v4)",
    "deep_swe": "retired: values kept, never used (v4)",
}


class FeedMinRowsError(ValueError):
    """A parser saw fewer rows than its row minimum: upstream drifted or broke."""


@dataclass(slots=True)
class FeedResult:
    values: dict[str, Any] = field(default_factory=dict)
    error: str | None = None
    rows: int | None = None


@dataclass(frozen=True, slots=True)
class PageSpec:
    feed: str
    url: str
    fields: Mapping[str, str]  # our key -> embedded page field
    primary: str  # a row counts toward the row minimum only with this key


PAGE_SPECS: Final = {
    s.feed: s
    for s in (
        PageSpec(
            "aa_page_lcr",
            f"{AA_SITE}/evaluations/artificial-analysis-long-context-reasoning",
            {"tb4": "terminalBench40", "lcr": "lcr"},
            "tb4",
        ),
        PageSpec(
            "aa_page_cyber",
            f"{AA_SITE}/evaluations/artificial-analysis-cyber-index",
            {"aa_cyber": "cyberIndex"},
            "aa_cyber",
        ),
        PageSpec(
            "aa_page_healthbench",
            f"{AA_SITE}/evaluations/healthbench",
            {"healthbench": "healthbench"},
            "healthbench",
        ),
        PageSpec(
            "aa_omniscience",
            f"{AA_SITE}/evaluations/omniscience",
            {"omniscience": "omniscience", "hallucination_rate": "hallucinationRate"},
            "omniscience",
        ),
    )
}
AA3D_URL: Final = f"{AA_SITE}/evaluations/aa-3d"

# About 60% of the rows each parser saw on 2026-11-09; aa_free is the
# contract's explicit 600 (727 rows today).
MIN_ROWS: Final[dict[str, int]] = {
    "openrouter": 275,
    "openrouter_key": 72,  # 60% of 121 store models on 2026-11-10
    "aa_free": 600,
    "aa_page_lcr": 17,
    "aa_page_cyber": 15,
    "aa_page_healthbench": 8,
    "aa_page_3d": 15,
    "aa_omniscience": 17,
    **boards.MIN_ROWS,
    "arena_lang_mean": 100,  # estimates: never observed (host blocked at build)
    "arena_european_mean": 100,
}
BOARD_FEEDS: Final = tuple(boards.FETCH) + ("arena_lang_mean", "arena_european_mean")
FEEDS: Final = (
    "openrouter",
    "openrouter_key",
    "aa_free",
    "aa_page_lcr",
    "aa_page_cyber",
    "aa_page_healthbench",
    "aa_page_3d",
    "aa_omniscience",
    *BOARD_FEEDS,
)
SOURCE_URL: Final[dict[str, str]] = {
    "openrouter": OPENROUTER_URL,
    "openrouter_key": "file://~/.pi/agent/models-store.json",
    "aa_free": AA_FREE_URL,
    "aa_page_3d": AA3D_URL,
    **{k: s.url for k, s in PAGE_SPECS.items()},
    **{b: str(spec["url"]) for b, spec in boards.FETCH.items()},
}
SOURCE_FETCH: Final[dict[str, str]] = {
    "openrouter": "GET; .data[].pricing USD per token x1e6; negative = alias sentinel, skipped",
    "openrouter_key": "local read; openrouter.models[].cost input/output, the price this key pays",
    "aa_free": "GET ?page=N with x-api-key header until pagination.has_more is false; "
    "AAI, index cost, domain indexes, pricing; effort from slug or name",
    "aa_page_lcr": "one GET; embedded fields terminalBench40 (tb4) and lcr per model record",
    "aa_page_cyber": "one GET; embedded cyberIndex (aa_cyber) per model record",
    "aa_page_healthbench": "one GET; embedded healthbench per model record",
    "aa_page_3d": "one GET; aa3dElo plus its 95% interval, board aa_3d",
    "aa_omniscience": "one GET; embedded omniscience and hallucinationRate (stored as factuality)",
    "arena_lang_mean": "mean of the cached Arena language boards (at least 5 present)",
    "arena_european_mean": "mean of French, German, Spanish, Polish, Russian Arena boards",
}


def log(msg: str) -> None:
    print(f"[refresh] {msg}", file=sys.stderr)


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse redirects so the API key never follows one to another host."""

    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: HTTPMessage,
        newurl: str,
    ) -> urllib.request.Request | None:
        return None


def _retryable(err: Exception) -> bool:
    if isinstance(err, urllib.error.HTTPError):
        return err.code == 429 or err.code >= 500
    return isinstance(err, OSError | HTTPException)


def _retry_after(err: Exception) -> float | None:
    """Seconds a 429 asked us to wait (integer or HTTP-date form), else None."""
    value = (
        err.headers.get("Retry-After")
        if isinstance(err, urllib.error.HTTPError)
        else None
    )
    if not value:
        return None
    try:
        return max(0.0, float(int(value)))
    except ValueError:
        pass
    try:
        when = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=UTC)
    return max(0.0, when.timestamp() - time.time())


def _retry_delay(
    err: Exception, tries: Counter[str], deadline: float | None
) -> float | None:
    """Seconds to sleep before the next attempt, or None to give up.

    429 and every other retryable error count their attempts separately.
    """
    if not _retryable(err):
        return None
    rate = isinstance(err, urllib.error.HTTPError) and err.code == 429
    schedule = RATE_BACKOFF if rate else RETRY_BACKOFF
    kind = "rate" if rate else "other"
    n = tries[kind]
    tries[kind] += 1
    if n >= len(schedule):
        return None
    asked = _retry_after(err) if rate else None
    if asked is not None:
        return None if deadline is None and asked > RETRY_AFTER_CAP else asked
    return schedule[n] * random.uniform(*RATE_JITTER) if rate else schedule[n]


def fetch(
    url: str,
    data: bytes | None = None,
    headers: Mapping[str, str] | None = None,
    *,
    redirects: bool = True,
    deadline: float | None = None,
) -> bytes:
    """One request, retried with backoff on 429, 5xx, timeouts, and connection errors.

    A 429 waits its Retry-After (a value over RETRY_AFTER_CAP raises when
    there is no deadline) or else backs off exponentially with jitter.  A
    backoff that would end past ``deadline`` (a time.monotonic value) is
    not taken; the error is raised instead.
    """
    tries: Counter[str] = Counter()
    while True:
        try:
            return _fetch_once(url, data, headers, redirects=redirects)
        except (OSError, HTTPException) as e:
            delay = _retry_delay(e, tries, deadline)
            late = deadline is not None and time.monotonic() + (delay or 0) > deadline
            if delay is None or late:
                raise
            time.sleep(delay)


def _fetch_once(
    url: str,
    data: bytes | None = None,
    headers: Mapping[str, str] | None = None,
    *,
    redirects: bool = True,
) -> bytes:
    req = urllib.request.Request(
        url, data=data, headers=dict(headers or {"User-Agent": UA})
    )
    opener = (
        urllib.request.build_opener()
        if redirects
        else urllib.request.build_opener(_NoRedirect)
    )
    with opener.open(req, timeout=TIMEOUT) as r:
        return r.read()


# --- registry skeleton ----------------------------------------------------------


def source_stub(name: str) -> dict[str, Any]:
    return {
        "name": name,
        "url": SOURCE_URL.get(name),
        "fetch": SOURCE_FETCH.get(name),
        "status": "never",
        "as_of": None,
        "error": None,
        "rows": None,
        "row_minimum": MIN_ROWS.get(name),
        "matched": None,
    }


def refresh_source_meta(reg: Reg) -> None:
    """Re-stamp the code-owned fields of every source this script knows."""
    for name in (*FEEDS, *RETIRED):
        src = reg["sources"].setdefault(name, source_stub(name))
        for k in ("name", "url", "fetch", "row_minimum"):
            fresh = source_stub(name)[k]
            if fresh is not None or k not in src:
                src[k] = fresh


def mark_retired(reg: Reg) -> None:
    for name, why in RETIRED.items():
        src = reg["sources"].setdefault(name, source_stub(name))
        src["status"] = "retired"
        src["error"] = why


def variant_stub() -> dict[str, Any]:
    return {
        "aa_slug": None,
        "aai": None,
        "aai_source": None,
        "index_cost_usd": None,
        "domains": dict.fromkeys(
            ("business", "health_med", "fin_acct", "strat_ops", "legal", "economics")
        ),
        "page": {"tb4": None, "lcr": None, "aa_cyber": None, "healthbench": None},
        "band": None,
        "confidence": None,
    }


def model_stub(mid: str) -> dict[str, Any]:
    return {
        "provider": mid.split("/", 1)[0],
        "display_name": None,
        "vendor": mid.split("/", 1)[0],
        "pricing": {"input": None, "output": None, "source": None},
        "aa_pricing": None,
        "variants": {},
        "boards": {},
        "last_seen": {},
        "match": derive_match(mid),
    }


def ensure_model(reg: Reg, mid: str) -> dict[str, Any]:
    m = reg["models"].setdefault(mid, model_stub(mid))
    for k, default in (("variants", {}), ("boards", {}), ("last_seen", {})):
        m.setdefault(k, copy.deepcopy(default))
    m.setdefault("pricing", {"input": None, "output": None, "source": None})
    return m


def derive_match(mid: str, override: Mapping[str, Any] | None = None) -> dict[str, Any]:
    """Feed keys derived from the roster ID by rule; override.match patches keys."""
    vendor, _, tail = mid.partition("/")
    base = re.sub(r"\[[^\]]*\]$", "", tail)  # claude-fable-5-1[1m] -> claude-fable-5-1
    dashed = base.replace(".", "-")
    m: dict[str, Any] = {
        "openrouter": f"{vendor}/{base}",
        "aa_slug": dashed,
        "board": [f"{vendor}/{base}", base, dashed],
    }
    m.update(MATCH_DEFAULTS.get(mid, {}))
    for k, v in ((override or {}).get("match") or {}).items():
        if v is not None:
            m[k] = v
    return m


# --- Pi and Claude roster ---------------------------------------------------------


def store_meta(store: Mapping[str, Any]) -> dict[str, Any]:
    ms = store.get("checkedAt")
    when = (
        datetime.fromtimestamp(ms / 1000, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        if isinstance(ms, int | float)
        else None
    )
    return {"checked_at": when, "count": len(store.get("models", []))}


def pi_levels(entry: Mapping[str, Any] | None) -> list[str]:
    """Thinking levels Pi accepts for a model, from its models-store entry."""
    if entry is None:
        return []
    level_map = entry.get("thinkingLevelMap")
    if level_map:
        return [k for k in THINKING if level_map.get(k) is not None]
    return list(PI_DEFAULT_LEVELS) if entry.get("reasoning") is True else ["off"]


def split_pi_ref(ref: str) -> tuple[str, str] | None:
    """(registry id, store id) for an OpenRouter ref, or None when skipped.

    A trailing thinking-level suffix is one Pi would misparse, so it goes;
    `:free` leaves the registry id but stays in the store id.
    """
    if not ref.startswith("openrouter/"):
        return None
    rest = ref[len("openrouter/") :]
    if rest.startswith("openrouter/"):  # meta-router alias, not a model
        return None
    rest = re.sub(r":(" + "|".join(THINKING) + r")$", "", rest)
    return rest.removesuffix(":free"), rest


def pi_roster_entries(
    enabled: Sequence[str], store_models: Sequence[Mapping[str, Any]]
) -> dict[str, dict[str, Any]]:
    """Roster entries from Pi's enabledModels and its models-store."""
    store = {m["id"]: m for m in store_models}
    out: dict[str, dict[str, Any]] = {}
    for ref in enabled:
        parsed = split_pi_ref(ref)
        if parsed is None:
            continue
        mid, sid = parsed
        if mid in out and sid.endswith(":free"):
            continue  # the paid route wins over its :free twin
        entry = store.get(sid)
        cost = (entry or {}).get("cost") or {}
        out[mid] = {
            "harness": "pi",
            "enabled": True,
            "model_ref": f"openrouter/{sid}",
            "model_param": None,
            "rosters": (["pi-zdr"] if entry else []) + ["pi-enabled"],
            "context_window": (entry or {}).get("contextWindow"),
            "pi_levels": pi_levels(entry),
            "price": {"input": cost.get("input"), "output": cost.get("output")}
            if entry and cost.get("input") is not None
            else None,
        }
    return out


def claude_roster_entry(mid: str, ok: bool, note: str | None = None) -> dict[str, Any]:
    tail = mid.split("/", 1)[1]
    base = re.sub(r"\[[^\]]*\]$", "", tail)
    fam = re.match(r"claude-([a-z]+)", base)
    e: dict[str, Any] = {
        "harness": "claude-code",
        "enabled": bool(ok),
        "model_ref": None,
        "model_param": fam.group(1) if fam else base,
        "rosters": [],
        "context_window": 1_000_000 if tail.endswith("[1m]") else None,
    }
    if note:
        e["note"] = note
    return e


def read_json(path: str) -> Any:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def claude_candidates(reg: Reg, host: str) -> list[str]:
    """Old host roster Claude IDs, the ~/.claude.json picker cache, overrides.*.probe."""
    ids: set[str] = set()
    old = (reg["hosts"].get(host) or {}).get("roster", {})
    ids.update(k for k, e in old.items() if e.get("harness") == "claude-code")
    ids.update(
        k
        for k, o in reg.get("overrides", {}).items()
        if k.startswith("anthropic/") and o.get("probe")
    )
    try:
        cache = read_json(CLAUDE_CACHE)
    except (OSError, ValueError) as e:
        log(f"claude cache unreadable ({e}); continuing")
        return sorted(ids)
    for opt in cache.get("additionalModelOptionsCache") or []:
        v = opt.get("value") if isinstance(opt, dict) else None
        if isinstance(v, str) and v.startswith("claude-"):
            ids.add("anthropic/" + v)
    return sorted(ids)


def cli_version(cmd: str) -> str | None:
    try:
        out = subprocess.run(
            [cmd, "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    return out or None


def probe_model_arg(mid: str) -> str:
    """CLI --model value: the family alias resolves the deployment's dated ID;
    a context-window suffix needs the exact form."""
    tail = mid.split("/", 1)[1]
    if tail.endswith("]"):
        return tail
    fam = re.match(r"claude-([a-z]+)", tail)
    return fam.group(1) if fam else tail


def probe_claude(ids: Sequence[str]) -> dict[str, str]:
    """{id: 'ok'|'error: ...'}.  Runs OUTSIDE sandboxed tool calls (needs the CLI's network)."""
    env = dict(os.environ, MAX_THINKING_TOKENS="0")
    out: dict[str, str] = {}
    for mid in ids:
        cmd = [
            "claude",
            "-p",
            "--model",
            probe_model_arg(mid),
            "--max-turns",
            "1",
            "Reply with the single word: ok",
        ]
        try:
            r = subprocess.run(
                cmd,
                check=False,
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
                stdin=subprocess.DEVNULL,
            )
            out[mid] = (
                "ok"
                if r.returncode == 0
                else "error: " + (r.stderr or r.stdout).strip()[:200]
            )
        except (OSError, subprocess.SubprocessError) as e:
            out[mid] = f"error: {e}"
        log(f"probe {mid}: {out[mid][:60]}")
    return out


def build_host(
    old_host: Mapping[str, Any] | None,
    *,
    pi_available: bool,
    pi_entries: Mapping[str, Any] | None,
    pi_meta: Mapping[str, Any] | None,
    claude_available: bool,
    claude_results: Mapping[str, str] | None,
    now: str,
) -> dict[str, Any]:
    """Merge roster truth for this host.  Nothing is deleted; dropped IDs are disabled."""
    host: dict[str, Any] = copy.deepcopy(dict(old_host or {}))
    roster: dict[str, dict[str, Any]] = host.get("roster") or {}
    for e in roster.values():
        is_pi = e.get("harness") == "pi"
        if is_pi and not pi_available:
            e.update(enabled=False, note="pi-missing")
        if not is_pi and not claude_available:
            e.update(enabled=False, note="claude-missing")
    if pi_available and pi_entries is not None:
        for k, e in roster.items():
            if e.get("harness") == "pi" and k not in pi_entries:
                e.update(enabled=False, note="not in enabledModels")
        for k, e in pi_entries.items():
            roster[k] = dict(e)
        host["pi_models_store"] = dict(pi_meta or {})
    for k, res in (claude_results or {}).items():
        ok = res == "ok"
        e = claude_roster_entry(k, ok, note=None if ok else res)
        old_ctx = roster.get(k, {}).get("context_window")
        if old_ctx and not e.get("context_window"):
            e["context_window"] = old_ctx
        roster[k] = e
    host["roster"] = roster
    host["harnesses"] = {
        "claude-code": {"healthy": claude_available},
        "pi": {"healthy": pi_available and pi_entries is not None},
    }
    host.setdefault("herdr", "env")
    host.setdefault("default_profile", "claude-code")
    host.setdefault("bedrock_aliases", {})
    host.setdefault("pi_models_store", None)
    host["probed_at"] = now
    host["probed_with"] = {
        "claude": (host.get("probed_with") or {}).get("claude"),
        "pi": (host.get("probed_with") or {}).get("pi"),
    }
    return host


# --- AA parsers (pure) ----------------------------------------------------------------

_EFFORT_NAMES: Final = {"non-reasoning": "off", **{e: e for e in THINKING}}
_SLUG_SUFFIX: Final = {"off": "-non-reasoning", **{e: f"-{e}" for e in THINKING[1:]}}
_PAREN_RE: Final = re.compile(r"\(([^()]*)\)\s*$")


def aa_effort(slug: str, name: str) -> tuple[str, str]:
    """(base slug, effort) for an AA row.

    Effort comes from the name's last parenthetical (the slug suffix alone is
    unreliable: `qwen3-max` is a model).  The suffix is stripped from the slug
    only when it agrees with that effort.
    """
    m = _PAREN_RE.search(name)
    tokens = [t.strip().lower() for t in m.group(1).split(",")] if m else []
    found = [_EFFORT_NAMES[t] for t in tokens if t in _EFFORT_NAMES]
    explicit = [e for e in found if e != "off"]
    effort = explicit[0] if explicit else ("off" if found else "single")
    suffix = _SLUG_SUFFIX.get(effort)
    if suffix and slug.endswith(suffix) and len(slug) > len(suffix):
        return slug[: -len(suffix)], effort
    return slug, effort


def _num(v: Any) -> float | None:
    return float(v) if isinstance(v, int | float) and not isinstance(v, bool) else None


def aa_domains(ev: Mapping[str, Any]) -> dict[str, float | None]:
    dom = {
        "fin_acct": ev.get("artificial_analysis_finance_and_accounting_index"),
        "strat_ops": ev.get("artificial_analysis_strategy_and_ops_index"),
        "legal": ev.get("artificial_analysis_legal_index"),
        "health_med": ev.get("artificial_analysis_healthcare_and_medical_index"),
        "economics": ev.get("artificial_analysis_economics_index"),
    }
    parts = [p for k in BUSINESS_PARTS if (p := _num(dom[k])) is not None]
    business = (
        round(sum(parts) / len(parts), 2) if len(parts) == len(BUSINESS_PARTS) else None
    )
    return {"business": business, **dom}


def parse_aa_free(
    pages: Sequence[Mapping[str, Any]], min_rows: int | None = None
) -> dict[str, dict[str, dict[str, Any]]]:
    """{base slug: {effort: variant fields}} from the free-tier API pages.

    The row minimum applies to every row seen; only scored variants are returned.
    """
    need = MIN_ROWS["aa_free"] if min_rows is None else min_rows
    seen = 0
    out: dict[str, dict[str, dict[str, Any]]] = {}
    for page in pages:
        for row in page.get("data", []):
            seen += 1
            ev = row.get("evaluations") or {}
            aai = _num(ev.get("artificial_analysis_intelligence_index"))
            if aai is None:
                continue
            base, effort = aa_effort(row["slug"], row.get("name", ""))
            pr = row.get("pricing") or {}
            cost = (row.get("artificial_analysis_intelligence_index_cost") or {}).get(
                "total_cost"
            )
            out.setdefault(base, {}).setdefault(
                effort,
                {
                    "aa_slug": row["slug"],
                    "aai": aai,
                    "index_cost_usd": _num(cost),
                    "domains": aa_domains(ev),
                    "aa_pricing": {
                        "input": pr.get("price_1m_input_tokens"),
                        "output": pr.get("price_1m_output_tokens"),
                    }
                    if pr.get("price_1m_input_tokens") is not None
                    and pr.get("price_1m_output_tokens") is not None
                    else None,
                    "display_name": _PAREN_RE.sub("", row.get("name", "")).strip()
                    or None,
                },
            )
    if seen < need:
        raise FeedMinRowsError(f"aa_free: {seen} rows, minimum {need}")
    return out


_RECORD_RE: Final = re.compile(
    r'(?:"id":"([^"]*)",)?"slug":"([^"]*)","name":"([^"]*)","shortName"'
)


def _unescape(raw: bytes | str) -> str:
    text = raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else raw
    return text.replace('\\\\"', '"').replace('\\"', '"')


def _records(text: str) -> Iterator[tuple[str | None, str, str, str]]:
    """(id, slug, name, record text) for each embedded model record."""
    ms = list(_RECORD_RE.finditer(text))
    for m, nxt in zip(ms, [*ms[1:], None], strict=True):
        end = nxt.start() if nxt else len(text)
        yield (
            m.group(1),
            m.group(2),
            m.group(3),
            text[m.end() : min(end, m.end() + SEGMENT_CAP)],
        )


def _field(seg: str, name: str) -> float | None:
    m = re.search(r'"' + re.escape(name) + r'":(null|-?[0-9][0-9.eE+-]*)', seg)
    return None if m is None or m.group(1) == "null" else float(m.group(1))


def parse_page(
    raw: bytes | str, spec: PageSpec, min_rows: int | None = None
) -> dict[str, dict[str, dict[str, float]]]:
    """{base slug: {effort: {key: value}}}; only the spec's fields are read."""
    need = MIN_ROWS[spec.feed] if min_rows is None else min_rows
    out: dict[str, dict[str, dict[str, float]]] = {}
    for _id, slug, name, seg in _records(_unescape(raw)):
        vals = {
            k: v for k, f in spec.fields.items() if (v := _field(seg, f)) is not None
        }
        if spec.primary not in vals:
            continue
        base, effort = aa_effort(slug, name)
        out.setdefault(base, {}).setdefault(effort, vals)
    rows = sum(len(e) for e in out.values())
    if rows < need:
        raise FeedMinRowsError(f"{spec.feed}: {rows} rows, minimum {need}")
    return out


_INTERVAL_RE: Final = re.compile(
    r'"([0-9a-f-]{36})":\{"elo":([0-9.]+),"lower95ci":([0-9.]+),"upper95ci":([0-9.]+)\}'
)


def parse_aa3d(
    raw: bytes | str, min_rows: int | None = None
) -> dict[str, dict[str, dict[str, float | None]]]:
    """{base slug: {effort: {score, ci}}}; ci is the half-width of the 95% interval."""
    need = MIN_ROWS["aa_page_3d"] if min_rows is None else min_rows
    text = _unescape(raw)
    intervals: dict[str, list[tuple[float, float, float]]] = {}
    for m in _INTERVAL_RE.finditer(text):
        intervals.setdefault(m.group(1), []).append(
            (float(m.group(2)), float(m.group(3)), float(m.group(4)))
        )
    out: dict[str, dict[str, dict[str, float | None]]] = {}
    for rid, slug, name, seg in _records(text):
        score = _field(seg, "aa3dElo")
        if score is None:
            continue
        ci = next(
            (
                round((hi - lo) / 2, 2)
                for elo, lo, hi in intervals.get(rid or "", [])
                if abs(elo - score) < 1e-6
            ),
            None,
        )
        base, effort = aa_effort(slug, name)
        out.setdefault(base, {}).setdefault(effort, {"score": score, "ci": ci})
    rows = sum(len(e) for e in out.values())
    if rows < need:
        raise FeedMinRowsError(f"aa_page_3d: {rows} rows, minimum {need}")
    return out


def parse_omniscience(
    raw: bytes | str, min_rows: int | None = None
) -> dict[str, dict[str, dict[str, float | None]]]:
    """{base slug: {effort: {omniscience, factuality}}}, factuality = 1 - hallucination rate."""
    rows = parse_page(
        raw,
        PAGE_SPECS["aa_omniscience"],
        min_rows=MIN_ROWS["aa_omniscience"] if min_rows is None else min_rows,
    )
    return {
        base: {
            effort: {
                "omniscience": v["omniscience"],
                "factuality": round(1 - v["hallucination_rate"], 4)
                if "hallucination_rate" in v
                else None,
            }
            for effort, v in efforts.items()
        }
        for base, efforts in rows.items()
    }


def parse_openrouter(
    data: Mapping[str, Any], min_rows: int | None = None
) -> dict[str, dict[str, float]]:
    need = MIN_ROWS["openrouter"] if min_rows is None else min_rows
    out: dict[str, dict[str, float]] = {}
    for row in data.get("data", []):
        try:
            p = float(row["pricing"]["prompt"]) * 1e6
            c = float(row["pricing"]["completion"]) * 1e6
        except (KeyError, TypeError, ValueError):
            continue
        if p < 0 or c < 0:
            continue
        out[row["id"]] = {"input": round(p, 6), "output": round(c, 6)}
    if len(out) < need:
        raise FeedMinRowsError(f"openrouter: {len(out)} rows, minimum {need}")
    return out


# --- matching ------------------------------------------------------------------------


def match_feed(reg: Reg, feed_key: str, rows: Mapping[str, Any]) -> dict[str, Any]:
    """{model_id: row_value} for models whose match[feed_key] hits the feed."""
    lowered = {k.lower(): v for k, v in rows.items()}
    out: dict[str, Any] = {}
    for mid, m in reg["models"].items():
        keys = m.get("match", {}).get(feed_key) or []
        for k in [keys] if isinstance(keys, str) else keys:
            if k.lower() in lowered:
                out[mid] = lowered[k.lower()]
                break
    return out


def board_key(key: str) -> str:
    """Compare form of a board key: "Claude Opus 5.5" and "claude-opus-5-5" agree."""
    return re.sub(r"[\s.]+", "-", key.strip().lower())


def match_board(reg: Reg, rows: Sequence[boards.Row]) -> dict[str, dict[str, Any]]:
    """{model_id: best board entry} over every row whose key a model's match lists."""
    by_key: dict[str, list[boards.Row]] = {}
    for r in rows:
        by_key.setdefault(board_key(r["key"]), []).append(r)
    out: dict[str, dict[str, Any]] = {}
    for mid, m in reg["models"].items():
        hits = [
            r
            for k in m.get("match", {}).get("board") or []
            for r in by_key.get(board_key(k), [])
        ]
        if hits:
            best = max(hits, key=lambda r: r["score"])
            out[mid] = {
                "score": best["score"],
                "ci": best["ci"],
                "effort": best["effort"],
                "votes": best["votes"],
            }
    return out


# --- feed fetchers ---------------------------------------------------------------------


def variants_by_model(
    reg: Reg, rows: Mapping[str, Mapping[str, Any]]
) -> dict[str, dict[str, Any]]:
    """{model_id: efforts-dict} for rows keyed by AA base slug."""
    return match_feed(reg, "aa_slug", rows)


def aa_free_result(
    reg: Reg, rows: Mapping[str, Mapping[str, Mapping[str, Any]]]
) -> FeedResult:
    values: dict[str, Any] = {}
    for mid, efforts in variants_by_model(reg, rows).items():
        payload: dict[str, Any] = {"variants": {}}
        for effort, v in efforts.items():
            payload["variants"][effort] = {
                k: v[k] for k in ("aa_slug", "aai", "index_cost_usd", "domains")
            }
            if v["aa_pricing"]:
                payload["aa_pricing"] = v["aa_pricing"]
            payload.setdefault("display_name", v["display_name"])
        values[mid] = payload
    return FeedResult(values=values, rows=sum(len(e) for e in rows.values()))


def page_result(
    reg: Reg, rows: Mapping[str, Mapping[str, Mapping[str, float | None]]]
) -> FeedResult:
    values = {
        mid: {"variants": {e: {"page": dict(v)} for e, v in efforts.items()}}
        for mid, efforts in variants_by_model(reg, rows).items()
    }
    return FeedResult(values=values, rows=sum(len(e) for e in rows.values()))


def board3d_result(
    reg: Reg, rows: Mapping[str, Mapping[str, Mapping[str, float | None]]]
) -> FeedResult:
    values: dict[str, Any] = {}
    for mid, efforts in variants_by_model(reg, rows).items():
        effort, best = max(efforts.items(), key=lambda kv: kv[1]["score"] or 0)
        values[mid] = {
            "boards": {
                "aa_3d": {
                    "score": best["score"],
                    "ci": best["ci"],
                    "effort": effort,
                    "votes": None,
                }
            }
        }
    return FeedResult(values=values, rows=sum(len(e) for e in rows.values()))


def parse_key_prices(
    store_models: Sequence[Mapping[str, Any]], min_rows: int | None = None
) -> dict[str, dict[str, Any]]:
    """{store id: key price} from Pi's models store, USD per million tokens."""
    need = MIN_ROWS["openrouter_key"] if min_rows is None else min_rows
    out: dict[str, dict[str, Any]] = {}
    for m in store_models:
        sid, cost = m.get("id"), m.get("cost") or {}
        if not isinstance(sid, str) or sid.startswith("openrouter/") or ":" in sid:
            continue
        i, o = cost.get("input"), cost.get("output")
        if isinstance(i, int | float) and isinstance(o, int | float):
            out[sid] = {"input": i, "output": o, "source": KEY_SOURCE}
    if len(out) < need:
        raise FeedMinRowsError(f"openrouter_key: {len(out)} rows, minimum {need}")
    return out


def feed_openrouter_key(reg: Reg, _cache: Cache) -> FeedResult:
    rows = parse_key_prices(read_json(PI_STORE)["openrouter"]["models"])
    matched = match_feed(reg, "openrouter", rows)
    return FeedResult(
        values={k: {"pricing": v} for k, v in matched.items()}, rows=len(rows)
    )


def feed_openrouter(reg: Reg, _cache: Cache) -> FeedResult:
    rows = parse_openrouter(json.loads(fetch(OPENROUTER_URL)))
    matched = match_feed(reg, "openrouter", rows)
    return FeedResult(
        values={k: {"pricing": v} for k, v in matched.items()}, rows=len(rows)
    )


def redact(text: str) -> str:
    """Replace the AA key and HF token (raw, stripped, repr forms) with `***`."""
    for var in ("AA_API_KEY", "HF_TOKEN"):
        raw = os.environ.get(var) or ""
        for form in sorted({raw, raw.strip(), repr(raw)[1:-1]}, key=len, reverse=True):
            if form:
                text = text.replace(form, REDACTED)
    return text


def feed_aa_free(reg: Reg, _cache: Cache) -> FeedResult:
    key = (os.environ.get("AA_API_KEY") or "").strip()
    if not key:
        return FeedResult(error="AA_API_KEY unset")
    if any(ord(c) < 32 or ord(c) == 127 for c in key):
        return FeedResult(error="AA_API_KEY contains control characters; refusing")
    pages: list[Mapping[str, Any]] = []
    for n in range(1, MAX_PAGES + 1):
        raw = fetch(
            f"{AA_FREE_URL}?page={n}",
            headers={"x-api-key": key, "User-Agent": UA},
            redirects=False,
        )
        page = json.loads(raw)
        pages.append(page)
        if not (page.get("pagination") or {}).get("has_more"):
            break
    return aa_free_result(reg, parse_aa_free(pages))


def make_page_feed(spec: PageSpec) -> FeedFn:
    def feed(reg: Reg, _cache: Cache) -> FeedResult:
        return page_result(reg, parse_page(fetch(spec.url), spec))

    return feed


def feed_aa_3d(reg: Reg, _cache: Cache) -> FeedResult:
    return board3d_result(reg, parse_aa3d(fetch(AA3D_URL)))


def feed_omniscience(reg: Reg, _cache: Cache) -> FeedResult:
    rows = parse_omniscience(fetch(PAGE_SPECS["aa_omniscience"].url))
    values = {
        mid: {"variants": {e: {"page": dict(v)} for e, v in efforts.items()}}
        for mid, efforts in variants_by_model(reg, rows).items()
    }
    return FeedResult(values=values, rows=sum(len(e) for e in rows.values()))


def hf_token() -> str | None:
    """HF_TOKEN from the environment, stripped; None if unset or unsafe to send."""
    token = (os.environ.get("HF_TOKEN") or "").strip()
    if any(ord(c) < 32 or ord(c) == 127 for c in token):
        log("warning: HF_TOKEN contains control characters; continuing anonymously")
        return None
    return token or None


def hf_headers(url: str, token: str | None) -> dict[str, str]:
    """Request headers for `url`; the bearer token goes to Hugging Face hosts only."""
    headers = {"User-Agent": UA}
    host = urllib.parse.urlsplit(url).hostname or ""
    if token and (host == HF_HOST or host.endswith("." + HF_HOST)):
        headers["Authorization"] = f"Bearer {token}"
    return headers


def cache_dir() -> str:
    """Arena page cache directory; reads the environment at call time."""
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "agents", "model-selection")


def arena_config(url: str) -> str:
    return urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)["config"][0]


def hub_sha(headers: Mapping[str, str], deadline: float) -> str:
    """The dataset's current Hub revision; raises OSError or ValueError on any failure."""
    info = json.loads(
        fetch(
            ARENA_DATASET_API,
            headers=headers,
            redirects="Authorization" not in headers,
            deadline=deadline,
        )
    )
    sha = info.get("sha") if isinstance(info, dict) else None
    if not isinstance(sha, str) or not sha:
        raise ValueError("no sha in the dataset info")
    return sha


def read_arena_cache(config: str, sha: str) -> list[Any] | None:
    """Cached pages for `config` if they were stored at revision `sha`."""
    try:
        with open(
            os.path.join(cache_dir(), f"arena-{config}.json"), encoding="utf-8"
        ) as f:
            stored = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(stored, dict) or stored.get("sha") != sha:
        return None
    pages = stored.get("pages")
    return pages if isinstance(pages, list) and pages else None


def write_arena_cache(config: str, sha: str, pages: Sequence[Any]) -> None:
    """Store pages atomically (temp file, then rename); a failure only costs a re-page."""
    path = os.path.join(cache_dir(), f"arena-{config}.json")
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            json.dump({"sha": sha, "pages": list(pages)}, f)
        os.replace(path + ".tmp", path)
    except OSError as e:
        log(f"arena cache not written: {e}")


def _page_rows(
    board: str, url: str, headers: Mapping[str, str], deadline: float
) -> list[Any]:
    pages: list[Any] = []
    for off in range(0, BOARD_MAX_PAGES * 100, 100):
        if off:
            time.sleep(PAGE_GAP)
        if time.monotonic() > deadline:
            raise TimeoutError(f"{board}: feed ran past {FEED_WALL} s")
        raw = fetch(
            f"{url}&offset={off}&length=100",
            headers=headers,
            redirects="Authorization" not in headers,
            deadline=deadline,
        )
        page = json.loads(raw)
        if not page.get("rows"):
            break
        pages.append(page)
        # Stop at the reported total: an offset past the end may be an HTTP error.
        if off + 100 >= int(page.get("num_rows_total") or 0):
            break
    return pages


def fetch_board(board: str) -> Any:
    """Raw payload for one board: bytes, or the list of pages for a paged board.

    A paged (Arena) config is re-paged only when its Hub revision changed.
    """
    spec = boards.FETCH[board]
    url, body = str(spec["url"]), spec["body"]
    headers = {"User-Agent": UA}
    if body:
        headers["Content-Type"] = "application/json"
    if not spec["paging"]:
        return fetch(url, data=body.encode() if body else None, headers=headers)
    deadline = time.monotonic() + FEED_WALL
    token = hf_token()
    config = arena_config(url)
    sha: str | None = None
    try:
        sha = hub_sha(hf_headers(ARENA_DATASET_API, token), deadline)
    except (OSError, ValueError, HTTPException) as e:
        log(f"{board}: Hub revision check failed ({redact(str(e))}); paging")
    cached = read_arena_cache(config, sha) if sha else None
    if sha and cached is not None:
        log(f"{board}: Hub revision {sha[:7]} unchanged; using cached pages")
        return cached
    pages = _page_rows(board, url, hf_headers(url, token), deadline)
    if sha:
        write_arena_cache(config, sha, pages)
    return pages


def parse_board(board: str, raw: Any) -> list[boards.Row]:
    if board in boards.ARENA_CATEGORY:
        return boards.parse_arena(raw, board)
    if board == "design_arena":
        return boards.parse_designarena(raw)
    if board == "eq_bench":
        return boards.parse_eqbench(raw)
    raise KeyError(board)


def board_result(reg: Reg, board: str, rows: Sequence[boards.Row]) -> FeedResult:
    matched = match_board(reg, rows)
    return FeedResult(
        values={mid: {"boards": {board: e}} for mid, e in matched.items()},
        rows=len(rows),
    )


def make_board_feed(board: str, shared: dict[str, Any]) -> FeedFn:
    """A board feed; boards with one URL share one fetch, or one failure, per run."""

    def feed(reg: Reg, cache: Cache) -> FeedResult:
        url = str(boards.FETCH[board]["url"])
        if url not in shared:
            try:
                shared[url] = fetch_board(board)
            except (OSError, ValueError, LookupError, HTTPException) as e:
                shared[url] = e
        raw = shared[url]
        if isinstance(raw, Exception):
            raise raw
        rows = parse_board(board, raw)
        cache[board] = rows
        return board_result(reg, board, rows)

    return feed


def lang_mean_rows(
    board: str, cache: Mapping[str, Sequence[boards.Row]], min_rows: int | None = None
) -> list[boards.Row]:
    need = MIN_ROWS[board] if min_rows is None else min_rows
    mean = (
        boards.arena_lang_mean
        if board == "arena_lang_mean"
        else boards.arena_european_mean
    )
    rows = mean(cache)
    if len(rows) < need:
        raise FeedMinRowsError(f"{board}: {len(rows)} rows, minimum {need}")
    return rows


def make_mean_feed(board: str) -> FeedFn:
    def feed(reg: Reg, cache: Cache) -> FeedResult:
        return board_result(reg, board, lang_mean_rows(board, cache))

    return feed


def build_feeds() -> dict[str, FeedFn]:
    feeds: dict[str, FeedFn] = {
        "openrouter": feed_openrouter,
        "openrouter_key": feed_openrouter_key,
        "aa_free": feed_aa_free,
        "aa_page_3d": feed_aa_3d,
        "aa_omniscience": feed_omniscience,
    }
    for name, spec in PAGE_SPECS.items():
        if name != "aa_omniscience":
            feeds[name] = make_page_feed(spec)
    shared: dict[str, Any] = {}
    for b in boards.FETCH:
        feeds[b] = make_board_feed(b, shared)
    feeds["arena_lang_mean"] = make_mean_feed("arena_lang_mean")
    feeds["arena_european_mean"] = make_mean_feed("arena_european_mean")
    return {k: feeds[k] for k in FEEDS}


# --- merge ---------------------------------------------------------------------------------


def _set(
    obj: dict[str, Any], key: str, new: Any, changes: list[str], label: str
) -> None:
    """Write a value; never null over a value."""
    if new is None or obj.get(key) == new:
        return
    changes.append(f"{label}.{key}: {obj.get(key)} -> {new}")
    obj[key] = new


def merge_variant(
    var: dict[str, Any],
    vals: Mapping[str, Any],
    changes: list[str],
    label: str,
    feed: str,
) -> None:
    for k, v in vals.items():
        if isinstance(v, Mapping):
            sub = var.setdefault(k, {})
            if sub is None:
                sub = var[k] = {}
            for sk, sv in v.items():
                _set(sub, sk, sv, changes, f"{label}.{k}")
        else:
            _set(var, k, v, changes, label)
    if vals.get("aai") is not None:
        var["aai_source"] = feed


def merge_board(
    m: dict[str, Any],
    board: str,
    entry: Mapping[str, Any],
    today: str,
    changes: list[str],
    mid: str,
) -> None:
    old = m["boards"].get(board)
    if (
        old
        and old.get("score") is not None
        and abs(entry["score"] - old["score"]) < ELO_DRIFT
    ):
        return
    new = {**entry, "as_of": today}
    if old != new:
        changes.append(
            f"{mid}.boards.{board}: {old and old.get('score')} -> {entry['score']}"
        )
    m["boards"][board] = new


def merge_price(
    m: dict[str, Any], vals: Mapping[str, Any], feed: str, changes: list[str], mid: str
) -> None:
    """Write a price unless the current one comes from a higher-ranked source."""
    cur = m["pricing"]
    src, old_src = vals.get("source") or feed, cur.get("source")
    if old_src not in (None, src) and PRICE_RANK.get(src, 0) <= PRICE_RANK.get(
        old_src, 0
    ):
        return
    if vals.get("input") is None or vals.get("output") is None:
        return
    new = {"input": vals["input"], "output": vals["output"], "source": src}
    if cur != new:  # == is numeric, so 4 and 4.0 are equal
        changes.append(f"{mid}.pricing: {_price_text(cur)} -> {_price_text(new)}")
        m["pricing"] = new


def _price_text(p: Mapping[str, Any]) -> str:
    def num(v: Any) -> str:
        return "none" if v is None else f"{v:g}"

    return f"{num(p.get('input'))}/{num(p.get('output'))} ({p.get('source')})"


def apply_feed(
    reg: Reg, feed: str, result: FeedResult, today: str, host: str
) -> list[str]:
    src = reg["sources"].setdefault(feed, source_stub(feed))
    changes: list[str] = []
    if result.error is not None or not result.values:
        src.update(
            status="failed",
            error=result.error
            or "zero rows matched (feed shape changed or all models absent)",
            fetched_by=host,
        )
        return changes
    src.update(
        status="ok",
        as_of=today,
        fetched_by=host,
        error=None,
        matched=len(result.values),
        rows=result.rows,
    )
    for mid, payload in result.values.items():
        m = ensure_model(reg, mid)
        m["last_seen"][feed] = today
        for effort, vals in (payload.get("variants") or {}).items():
            var = m["variants"].setdefault(effort, variant_stub())
            merge_variant(var, vals, changes, f"{mid}.{effort}", feed)
        for board, entry in (payload.get("boards") or {}).items():
            merge_board(m, board, entry, today, changes, mid)
        if payload.get("pricing"):
            merge_price(m, payload["pricing"], feed, changes, mid)
        if payload.get("aa_pricing"):
            _set(m, "aa_pricing", payload["aa_pricing"], changes, mid)
            if m["pricing"].get("source") is None:
                merge_price(m, payload["aa_pricing"], feed, changes, mid)
        if payload.get("display_name") and not m.get("display_name"):
            m["display_name"] = payload["display_name"]
    return changes


def run_feeds(
    reg: Reg,
    feeds: Mapping[str, FeedFn],
    skip: Sequence[str],
    today: str,
    host: str,
    cache: Cache,
) -> list[str]:
    changes: list[str] = []
    for name, fn in feeds.items():
        src = reg["sources"].setdefault(name, source_stub(name))
        if name in skip:
            src.update(status="skipped", error="--skip", fetched_by=host)
            continue
        try:
            result = fn(reg, cache)
        except (
            OSError,
            LookupError,
            TypeError,
            AttributeError,
            ValueError,
            HTTPException,
            boards.MinRowsError,
        ) as e:
            result = FeedResult(error=f"{type(e).__name__}: {e}"[:300])
        if result.error:
            result.error = redact(result.error)
        changes += apply_feed(reg, name, result, today, host)
        log(
            f"{name}: {src['status']}"
            + (
                f" ({src['error']})"
                if src.get("error")
                else f", {src.get('matched')} matched"
            )
        )
    return changes


def apply_overrides(reg: Reg) -> None:
    """Re-derive match keys; create track-only models.  Never edits `overrides`."""
    overrides = reg.get("overrides", {})
    for mid, o in overrides.items():
        if o.get("track_only"):
            ensure_model(reg, mid)["track_only"] = True
    for mid, m in reg["models"].items():
        m["match"] = derive_match(mid, overrides.get(mid))


def derive_variants(reg: Reg) -> None:
    """Band and confidence per variant; placement-only variants get a stub."""
    policy = reg["policy"]
    for mid, ov in reg.get("overrides", {}).items():
        if mid in reg["models"]:
            for effort in ov.get("placements", {}):
                reg["models"][mid]["variants"].setdefault(effort, variant_stub())
    for mid, m in reg["models"].items():
        for effort, var in m["variants"].items():
            aai, conf, source = registry.effective_aai(reg, mid, effort)
            var["band"] = registry.band_of(aai, mid, policy)
            var["confidence"] = conf
            if source == "placement":
                var["aai_source"] = "placement"
            elif var.get("aai") is None:
                var["aai_source"] = None
            else:
                var["aai_source"] = "aa_free"


# --- gates ------------------------------------------------------------------------------


def hand_owned_errors(
    reg: Reg, policy: Mapping[str, Any], overrides: Mapping[str, Any]
) -> list[str]:
    errs = []
    if reg.get("policy") != policy:
        errs.append("policy changed during refresh")
    if reg.get("overrides") != overrides:
        errs.append("overrides changed during refresh")
    return errs


def finalize(reg: Reg) -> None:
    """Overrides then derived bands; run after the feeds."""
    apply_overrides(reg)
    derive_variants(reg)


def critical_ok(reg: Reg, host: str) -> bool:
    h = reg["hosts"].get(host)
    return bool(h) and any(e.get("enabled") for e in h["roster"].values())


def write_registry(reg: Reg, path: str) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(reg, f, indent=2, sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    if os.path.exists(path):
        shutil.copyfile(path, path + ".bak")  # readers never see `path` missing
    os.replace(tmp, path)


def notify(summary: str, body: str) -> None:
    env = dict(os.environ)
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{os.getuid()}/bus")
    try:
        subprocess.run(
            ["notify-send", "-a", "model-selection", summary, body],
            env=env,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as e:
        log(f"notify-send unavailable ({e})")


# --- main ---------------------------------------------------------------------------------


def refresh_pi(
    reg: Reg, host: str, today: str
) -> tuple[bool, dict[str, Any] | None, dict[str, Any] | None]:
    """(pi_available, roster entries, store meta); records the pi_roster source."""
    src = reg["sources"].setdefault("pi_roster", source_stub("pi_roster"))
    src.update(
        name="Pi enabledModels and models-store",
        url="file://~/.pi/agent/{settings,models-store}.json",
        fetch="enabledModels[] intersected with openrouter.models[].id (pi-zdr); enabledModels alone (pi-enabled)",
    )
    if not (os.path.exists(PI_SETTINGS) and cli_version("pi")):
        src.update(
            status="skipped", error="pi not available on this host", fetched_by=host
        )
        return False, None, None
    try:
        store = read_json(PI_STORE)["openrouter"]
        entries = pi_roster_entries(
            read_json(PI_SETTINGS).get("enabledModels", []), store["models"]
        )
        if len(entries) < PI_MIN_ENTRIES or len(store["models"]) < PI_MIN_STORE:
            raise ValueError(
                f"Pi read below the row minimum: {len(entries)} enabled (min {PI_MIN_ENTRIES}),"
                f" {len(store['models'])} store models (min {PI_MIN_STORE})"
            )
    except (OSError, ValueError, LookupError, TypeError) as e:
        src.update(status="failed", error=str(e), fetched_by=host)
        return True, None, None
    src.update(
        status="ok",
        as_of=today,
        fetched_by=host,
        error=None,
        matched=len(entries),
        rows=len(store["models"]),
    )
    return True, entries, store_meta(store)


def refresh_claude(
    reg: Reg, host: str, today: str, force: bool, no_probe: bool
) -> tuple[bool, dict[str, str] | None, str | None]:
    """(claude_available, probe results, version); records the claude_roster source."""
    src = reg["sources"].setdefault("claude_roster", source_stub("claude_roster"))
    src.update(
        name="Claude Code deployment roster",
        url="file://~/.claude.json",
        fetch="candidates: old roster + additionalModelOptionsCache + overrides.*.probe; truth: claude -p probe",
    )
    version = cli_version("claude")
    if version is None:
        src.update(
            status="skipped",
            error="claude CLI not available on this host",
            fetched_by=host,
        )
        return False, None, None
    old_host = reg["hosts"].get(host) or {}
    old_roster = old_host.get("roster", {})
    if no_probe:
        return True, None, version
    cands = claude_candidates(reg, host)
    stale = (old_host.get("probed_with") or {}).get("claude") != version
    new_ids = [c for c in cands if c not in old_roster]
    if not (force or stale or new_ids):
        src.update(status="ok", as_of=today, fetched_by=host, error=None)
        log(f"claude {version}: roster unchanged, probe skipped")
        return True, None, version
    targets = cands if (force or stale) else new_ids
    log(f"claude {version}: probing {len(targets)} candidate(s)")
    results = probe_claude(targets)
    if any(v == "ok" for v in results.values()):
        src.update(
            status="ok",
            as_of=today,
            fetched_by=host,
            error=None,
            matched=sum(v == "ok" for v in results.values()),
        )
        return True, results, version
    src.update(
        status="failed", error="every probe errored; prior roster kept", fetched_by=host
    )
    return True, None, version


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--registry", default=os.environ.get("MODEL_BENCHMARKS", DEFAULT_REGISTRY)
    )
    ap.add_argument(
        "--host",
        default=os.environ.get(
            "MODEL_SELECTION_HOST", socket.gethostname().split(".")[0]
        ),
    )
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument(
        "--probe", action="store_true", help="force the Claude entitlement probe"
    )
    ap.add_argument("--no-probe", action="store_true")
    ap.add_argument(
        "--skip",
        action="append",
        default=[],
        choices=FEEDS,
        help="skip a feed (repeatable)",
    )
    return ap


def main(argv: Sequence[str] | None = None) -> int:
    a = build_parser().parse_args(argv)
    try:
        reg = registry.load(a.registry)
    except registry.RegistryError as e:
        log(str(e))
        return 2
    policy, overrides = (
        copy.deepcopy(reg["policy"]),
        copy.deepcopy(reg.get("overrides", {})),
    )
    reg.setdefault("sources", {})
    reg.setdefault("models", {})
    reg.setdefault("hosts", {})
    refresh_source_meta(reg)
    mark_retired(reg)

    ts = now()
    today = ts[:10]
    pi_ok, pi_entries, pi_meta = refresh_pi(reg, a.host, today)
    claude_ok, claude_results, cv = refresh_claude(
        reg, a.host, today, a.probe, a.no_probe
    )
    host = build_host(
        reg["hosts"].get(a.host),
        pi_available=pi_ok,
        pi_entries=pi_entries,
        pi_meta=pi_meta,
        claude_available=claude_ok,
        claude_results=claude_results,
        now=ts,
    )
    if claude_results is not None:
        host["probed_with"]["claude"] = cv
    if pi_ok:
        host["probed_with"]["pi"] = cli_version("pi")
    reg["hosts"][a.host] = host
    for mid in host["roster"]:
        ensure_model(reg, mid)
    apply_overrides(reg)  # match keys before the feeds run

    changes = run_feeds(reg, build_feeds(), a.skip, today, a.host, {})
    finalize(reg)
    reg["updated_at"] = ts

    errs = registry.validate(reg) + hand_owned_errors(reg, policy, overrides)
    if errs:
        for e in errs[:30]:
            log(f"INVALID: {e}")
        log(f"GATE FAILED: {len(errs)} error(s); registry NOT written")
        return 3
    if not critical_ok(reg, a.host):
        log("GATE FAILED: host has no enabled roster entry; registry NOT written")
        return 2

    if a.dry_run:
        print(
            json.dumps(
                {
                    "host": a.host,
                    "changes": changes,
                    "sources": {k: v["status"] for k, v in reg["sources"].items()},
                },
                indent=2,
            )
        )
        return 0
    write_registry(reg, a.registry)
    log(f"wrote {a.registry}: {len(changes)} change(s)")
    for c in changes:
        log(f"  {c}")
    if changes:
        notify(
            f"model-benchmarks.json: {len(changes)} change(s)",
            "\n".join(changes[:12]) + ("\n..." if len(changes) > 12 else ""),
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
