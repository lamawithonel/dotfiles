#!/usr/bin/env python3
"""Sole writer of the model-router registry (~/.agents/model-benchmarks.json).

Phases, each independently failable (a failed fetch keeps old values):

  1. roster      Pi enabledModels + Claude candidates (cache, overrides, old roster)
  2. probe       `claude -p` per Claude candidate, only when the CLI version changed
  3. openrouter  pricing + context windows
  4. aa_api      AA Intelligence / Coding indices, Terminal-Bench 2.1, pricing fallback
  5. aa_omni     AA Omniscience index + hallucination rate (stored inverted as factuality)
  6. deep_swe, eq_bench, design_arena   leaderboards
  7. overrides   hand-owned block merged on top
  8. validate    JSON Schema (schema/model-benchmarks.schema.json) + invariants
  9. write       atomic, one .bak generation, notify-send on change

Flags: --dry-run (print changes, no write), --probe (force Claude probe),
--no-probe, --skip FEED (repeatable), --registry PATH, --host NAME.

Prime directive: a number you did not fetch does not go in the file.
"""

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.join(HERE, "..", "schema", "model-benchmarks.schema.json")
DEFAULT_REGISTRY = os.path.expanduser("~/.agents/model-benchmarks.json")
PI_SETTINGS = os.path.expanduser("~/.pi/agent/settings.json")
CLAUDE_CACHE = os.path.expanduser("~/.claude.json")
UA = "Mozilla/5.0 (X11; Linux x86_64) model-router/3"
TIMEOUT = 45
ELO_FIELDS = ("eq_bench", "design_arena")
ELO_DRIFT = 10  # arena ELO recomputes ~2-hourly; damp churn below this
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
FEEDS = (
    "openrouter",
    "aa_api",
    "aa_omniscience",
    "deep_swe",
    "eq_bench",
    "design_arena",
)
SOURCE_META = {
    "openrouter": {
        "name": "OpenRouter models API",
        "url": "https://openrouter.ai/api/v1/models",
        "fetch": "GET; .data[].pricing USD per token x1e6; negative = routing-alias sentinel, skipped",
    },
    "aa_api": {
        "name": "Artificial Analysis API v2",
        "url": "https://artificialanalysis.ai/api/v2/data/llms/models",
        "fetch": "GET with x-api-key (AA_API_KEY); evaluations.artificial_analysis_{intelligence,coding}_index, terminalbench_v2_1 (fraction, stored x100), pricing fallback",
        "primary_version": "2.1",
    },
    "aa_omniscience": {
        "name": "Artificial Analysis Omniscience",
        "url": "https://artificialanalysis.ai/evaluations/omniscience",
        "fetch": "GET page; Next.js flight data; per slug: omniscience, omniscienceBreakdown.hallucinationRate (stored as aa_factuality = 1 - rate)",
    },
    "deep_swe": {
        "name": "Datacurve DeepSWE v1.1",
        "url": "https://deepswe.datacurve.ai/",
        "fetch": "GET; server-rendered table (model, Pass@1 percent); all rows mini-swe-agent",
    },
    "eq_bench": {
        "name": "EQ-Bench 4",
        "url": "https://eqbench.com/eqbench4/eqbench4_data.js",
        "fetch": "GET; strip 'const EQBENCH4_DATA = ' and trailing ';'; .models[] {model, elo}",
    },
    "design_arena": {
        "name": "Design Arena, Website category",
        "url": "https://www.designarena.ai/api/leaderboard",
        "fetch": "POST {arenaType:models, category:website}; .data[] {modelId, elo}",
    },
    "pi_roster": {
        "name": "Pi scoped models",
        "url": "file://~/.pi/agent/settings.json",
        "fetch": "enabledModels[]",
    },
    "claude_roster": {
        "name": "Claude Code deployment roster",
        "url": "file://~/.claude.json",
        "fetch": "candidates: old roster + additionalModelOptionsCache + overrides.*.probe; truth: claude -p probe",
    },
}


def log(msg):
    print(f"[refresh] {msg}", file=sys.stderr)


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def fetch(url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read().decode("utf-8", errors="replace")


# --- registry skeleton --------------------------------------------------------


def source_stub(name):
    meta: dict[str, object] = dict(SOURCE_META.get(name, {"name": name}))
    meta.update({"status": "never", "as_of": None, "fetched_by": None, "error": None})
    return meta


def empty_registry():
    return {
        "schema_version": 3,
        "updated_at": now(),
        "notes": [
            (
                "Unified model-router registry.  Written by skills/model-router/scripts/refresh-benchmarks.py; "
                "edit only the overrides block by hand.  Schema: skills/model-router/schema/model-benchmarks.schema.json."
            )
        ],
        "sources": {
            n: source_stub(n) for n in list(FEEDS) + ["pi_roster", "claude_roster"]
        },
        "overrides": {},
        "models": {},
        "hosts": {},
    }


def model_stub(mid):
    return {
        "provider": mid.split("/", 1)[0],
        "display_name": None,
        "context_window": None,
        "match": derive_match(mid),
        "benchmarks": {k: None for k in BENCH_FIELDS},
        "benchmark_versions": {},
        "benchmark_notes": {},
        "pricing": {
            "prompt_cost_per_m": None,
            "completion_cost_per_m": None,
            "source": None,
        },
        "last_seen": {},
    }


def ensure_model(reg, mid):
    m = reg["models"].setdefault(mid, model_stub(mid))
    for k in BENCH_FIELDS:
        m["benchmarks"].setdefault(k, None)
    m.setdefault("last_seen", {})
    m.setdefault("benchmark_versions", {})
    m.setdefault("benchmark_notes", {})
    return m


def derive_match(mid, override=None):
    """Feed keys derived from the roster id by rule; override.match patches keys."""
    vendor, tail = mid.split("/", 1)
    base = re.sub(r"\[[^\]]*\]$", "", tail)  # claude-fable-5-1[1m] -> claude-fable-5-1
    dashed = base.replace(".", "-")
    m = {
        "openrouter": f"{vendor}/{base}",
        "aa_slug": dashed,
        "deepswe": [base, dashed],
        "eqbench": [f"{vendor}/{base}", base, dashed],
        "designarena": [base, dashed],
    }
    if override and override.get("match"):
        for k, v in override["match"].items():
            if v is not None:
                m[k] = v
    return m


# --- roster ---------------------------------------------------------------------


def pi_roster_entries(enabled_models):
    """Roster entries from Pi's enabledModels list."""
    out = {}
    local = [x for x in enabled_models if x.startswith(("llama-swap/", "llama-cpp/"))]
    for ref in enabled_models:
        if not ref.startswith("openrouter/"):
            continue
        mid = ref[len("openrouter/") :]
        if mid.startswith(
            "openrouter/"
        ):  # openrouter/openrouter/auto*: meta-router alias
            continue
        out[mid] = {
            "enabled": True,
            "native_harness": ["pi"],
            "execution": {
                "pi": {"channel": "native", "model_ref": ref},
                "claude-code": {
                    "channel": "external",
                    "command": f"pi --offline --model '{ref}' -p \"$(cat payload.md)\" --no-session",
                },
            },
            "context_window": None,
        }
    if local:
        prefix = local[0].split("/", 1)[0]
        out[f"local/{prefix}"] = {
            "enabled": True,
            "native_harness": ["pi"],
            "is_class_entry": True,
            "count": len(local),
            "execution": {
                "pi": {"channel": "native", "model_ref": f"{prefix}/<name>"},
                "claude-code": {
                    "channel": "external",
                    "command": f"pi --offline --model '{prefix}/<name>' -p \"$(cat payload.md)\" --no-session",
                },
            },
            "context_window": None,
            "pricing": {
                "prompt_cost_per_m": 0.0,
                "completion_cost_per_m": 0.0,
                "source": "local",
                "note": "Host compute only; the router's epsilon floor keeps V finite.",
            },
            "note": f"Class entry for {len(local)} local quants; discover names with: jq -r '.enabledModels[] | select(startswith(\"{prefix}/\"))' ~/.pi/agent/settings.json",
        }
    return out


def claude_roster_entry(mid, ok, note=None):
    tail = mid.split("/", 1)[1]
    base = re.sub(r"\[[^\]]*\]$", "", tail)
    fam = re.match(r"claude-([a-z]+)", base)
    param = fam.group(1) if fam else base
    e = {
        "enabled": bool(ok),
        "native_harness": ["claude-code"],
        "execution": {
            "claude-code": {"channel": "native", "tool": "Agent", "model_param": param},
            "pi": {
                "channel": "external",
                "command": f'claude -p --offline --model {tail} "$(cat payload.md)"',
            },
        },
        "context_window": 1_000_000 if tail.endswith("[1m]") else None,
    }
    if note:
        e["note"] = note
    return e


def read_pi_enabled():
    with open(PI_SETTINGS) as f:
        return json.load(f).get("enabledModels", [])


def claude_candidates(reg, host):
    """Union of: old host roster anthropic ids, ~/.claude.json picker cache, overrides.*.probe."""
    ids = set()
    old = (reg["hosts"].get(host) or {}).get("roster", {})
    ids.update(k for k in old if k.startswith("anthropic/"))
    ids.update(
        k
        for k, o in reg["overrides"].items()
        if k.startswith("anthropic/") and o.get("probe")
    )
    try:
        with open(CLAUDE_CACHE) as f:
            cache = json.load(f)
        for opt in cache.get("additionalModelOptionsCache") or []:
            v = opt.get("value") if isinstance(opt, dict) else None
            if isinstance(v, str) and v.startswith("claude-"):
                ids.add("anthropic/" + v)
    except Exception as e:  # noqa: BLE001 -- cache is best-effort
        log(f"claude cache unreadable ({e}); continuing")
    return sorted(ids)


def claude_version():
    try:
        return (
            subprocess.run(
                ["claude", "--version"],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            ).stdout.strip()
            or None
        )
    except Exception:  # noqa: BLE001
        return None


def pi_version():
    try:
        return (
            subprocess.run(
                ["pi", "--version"],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            ).stdout.strip()
            or None
        )
    except Exception:  # noqa: BLE001
        return None


def probe_model_arg(mid):
    """CLI --model value: the family alias (opus/sonnet/haiku/fable) resolves the deployment's
    dated id, which the roster id does not carry; a context-window suffix needs the exact form."""
    tail = mid.split("/", 1)[1]
    if tail.endswith("]"):
        return tail
    fam = re.match(r"claude-([a-z]+)", tail)
    return fam.group(1) if fam else tail


def probe_claude(ids):
    """{id: 'ok'|'error: ...'}.  Runs OUTSIDE sandboxed tool calls (needs the CLI's network)."""
    env = dict(os.environ, MAX_THINKING_TOKENS="0")
    out = {}
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
        except Exception as e:  # noqa: BLE001
            out[mid] = f"error: {e}"
        log(f"probe {mid}: {out[mid][:60]}")
    return out


def build_host(
    old_roster,
    pi_available,
    pi_entries,
    claude_available,
    claude_results,
    old_host,
    now,
):
    """Merge roster truth for this host.  Nothing is deleted; dropped ids are disabled."""
    roster = {k: dict(v) for k, v in (old_roster or {}).items()}
    old_pw = (old_host or {}).get("probed_with") or {}
    for k, v in roster.items():
        is_pi = "pi" in v.get("native_harness", [])
        if is_pi and not pi_available:
            v["enabled"] = False
            v["note"] = "pi-missing"
        if (not is_pi) and not claude_available:
            v["enabled"] = False
            v["note"] = "claude-missing"
    if pi_available and pi_entries is not None:
        for k, v in roster.items():
            if "pi" in v.get("native_harness", []) and k not in pi_entries:
                v["enabled"] = False
                v["note"] = "not in enabledModels"
        for k, v in pi_entries.items():
            keep = roster.get(k, {})
            merged = dict(v)
            if keep.get("context_window") and not merged.get("context_window"):
                merged["context_window"] = keep["context_window"]
            roster[k] = merged
    if claude_available and claude_results is not None:
        for k, res in claude_results.items():
            ok = res == "ok"
            e = claude_roster_entry(k, ok, note=None if ok else res)
            if roster.get(k, {}).get("context_window") and not e.get("context_window"):
                e["context_window"] = roster[k]["context_window"]
            roster[k] = e
    return {
        "probed_at": now,
        "probed_with": {"claude": old_pw.get("claude"), "pi": old_pw.get("pi")},
        "channels": {"pi": bool(pi_available), "claude-code": bool(claude_available)},
        "roster": roster,
    }


# --- feed parsers (pure) ----------------------------------------------------------


class FeedResult:
    def __init__(self, values=None, error=None):
        self.values = values or {}
        self.error = error


def parse_openrouter(data):
    out = {}
    for row in data.get("data", []):
        try:
            p = float(row["pricing"]["prompt"]) * 1e6
            c = float(row["pricing"]["completion"]) * 1e6
        except (KeyError, TypeError, ValueError):
            continue
        if p < 0 or c < 0:
            continue
        out[row["id"]] = {
            "pricing": {
                "prompt_cost_per_m": round(p, 6),
                "completion_cost_per_m": round(c, 6),
            },
            "context_window": row.get("context_length"),
        }
    return out


def parse_aa_api(data):
    out = {}
    for row in data.get("data", []):
        ev = row.get("evaluations") or {}
        pr = row.get("pricing") or {}
        tb = ev.get("terminalbench_v2_1")
        vals = {
            "aa_intelligence": ev.get("artificial_analysis_intelligence_index"),
            "aa_coding": ev.get("artificial_analysis_coding_index"),
            "terminal_bench": round(tb * 100, 2)
            if isinstance(tb, (int, float))
            else None,
            "display_name": row.get("name"),
        }
        if (
            pr.get("price_1m_input_tokens") is not None
            and pr.get("price_1m_output_tokens") is not None
        ):
            vals["pricing"] = {
                "prompt_cost_per_m": pr["price_1m_input_tokens"],
                "completion_cost_per_m": pr["price_1m_output_tokens"],
            }
        out[row["slug"]] = vals
    return out


def _flight_text(html):
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', html, re.DOTALL)
    return "".join(c.encode().decode("unicode_escape", errors="ignore") for c in chunks)


def parse_omniscience(html):
    s = _flight_text(html)
    out = {}
    for m in re.finditer(r'"slug":"([a-z0-9-]+)","name":"([^"]*)"', s):
        slug = m.group(1)
        if slug in out:
            continue
        seg = s[m.end() : m.end() + 8000]
        o = re.search(r'"omniscience":(-?[0-9.]+)', seg)
        h = re.search(r'"hallucinationRate":(-?[0-9.]+)', seg)
        if not o:
            continue
        out[slug] = {
            "aa_omniscience": float(o.group(1)),
            "aa_factuality": round(1 - float(h.group(1)), 4) if h else None,
            "display_name": m.group(2),
        }
    return out


def parse_deepswe(html):
    """Rows of the server-rendered table: `<model> [ <effort> ] <pct> %` once tags are stripped.

    Tag stripping puts every cell on its own line, so the number and its
    percent sign are separate lines; a `[effort]` bracket may sit between
    the model name and the number.  First occurrence wins (the 'Best'
    table precedes the all-efforts table).
    """
    text = re.sub(r"<[^>]+>", "\n", html)
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    out = {}
    for i, ln in enumerate(lines):
        combined = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s*%", ln)
        if combined:
            num, j = float(combined.group(1)), i - 1
        elif ln == "%" and i > 0 and re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", lines[i - 1]):
            num, j = float(lines[i - 1]), i - 2
        else:
            continue
        if j >= 3 and lines[j] == "]" and lines[j - 2] == "[":
            j -= 3
        name = lines[j] if j >= 0 else ""
        if (
            name
            and not re.fullmatch(r"[0-9.%±$]+", name)
            and name.lower() not in ("pass@1", "model")
        ):
            out.setdefault(name.lower(), num)
    return out


def parse_eqbench(js):
    body = re.sub(r"^\s*//[^\n]*\n", "", js, count=1)
    body = re.sub(r"^\s*const\s+\w+\s*=\s*", "", body).rstrip().rstrip(";")
    data = json.loads(body)
    return {
        m["model"].lower(): float(m["elo"])
        for m in data.get("models", [])
        if m.get("elo") is not None
    }


def parse_designarena(data):
    return {
        r["modelId"].lower(): float(r["elo"])
        for r in data.get("data", [])
        if r.get("elo") is not None
    }


def match_feed(reg, feed_key, rows):
    """{model_id: row_value} for models whose match[feed_key] hits the feed."""
    out = {}
    for mid, m in reg["models"].items():
        keys = m["match"].get(feed_key) or []
        if isinstance(keys, str):
            keys = [keys]
        for k in keys:
            v = rows.get(k.lower()) if isinstance(rows, dict) else None
            if v is not None:
                out[mid] = v
                break
    return out


# --- feed fetchers ----------------------------------------------------------------


def feed_openrouter(reg):
    rows = parse_openrouter(json.loads(fetch(SOURCE_META["openrouter"]["url"])))
    return FeedResult(values=match_feed(reg, "openrouter", rows))


def feed_aa_api(reg):
    key = os.environ.get("AA_API_KEY")
    if not key:
        return FeedResult(error="AA_API_KEY unset")
    raw = fetch(
        SOURCE_META["aa_api"]["url"], headers={"x-api-key": key, "User-Agent": UA}
    )
    rows = parse_aa_api(json.loads(raw))
    return FeedResult(values=match_feed(reg, "aa_slug", rows))


def feed_aa_omniscience(reg):
    rows = parse_omniscience(fetch(SOURCE_META["aa_omniscience"]["url"]))
    return FeedResult(values=match_feed(reg, "aa_slug", rows))


def feed_deep_swe(reg):
    rows = parse_deepswe(fetch(SOURCE_META["deep_swe"]["url"]))
    return FeedResult(
        values={k: {"deep_swe": v} for k, v in match_feed(reg, "deepswe", rows).items()}
    )


def feed_eq_bench(reg):
    rows = parse_eqbench(fetch(SOURCE_META["eq_bench"]["url"]))
    return FeedResult(
        values={k: {"eq_bench": v} for k, v in match_feed(reg, "eqbench", rows).items()}
    )


def feed_design_arena(reg):
    raw = fetch(
        SOURCE_META["design_arena"]["url"],
        data=json.dumps({"arenaType": "models", "category": "website"}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": UA},
    )
    rows = parse_designarena(json.loads(raw))
    return FeedResult(
        values={
            k: {"design_arena": v}
            for k, v in match_feed(reg, "designarena", rows).items()
        }
    )


FEED_FN = {
    "openrouter": feed_openrouter,
    "aa_api": feed_aa_api,
    "aa_omniscience": feed_aa_omniscience,
    "deep_swe": feed_deep_swe,
    "eq_bench": feed_eq_bench,
    "design_arena": feed_design_arena,
}


# --- merge ----------------------------------------------------------------------------


def _set(model, field, new, changes, mid):
    """Write a benchmark value; never null over a value; damp ELO jitter."""
    if new is None:
        return
    old = model["benchmarks"].get(field)
    if field in ELO_FIELDS and old is not None and abs(new - old) < ELO_DRIFT:
        return
    if old == new:
        return
    model["benchmarks"][field] = new
    changes.append(f"{mid}.{field}: {old} -> {new}")


def apply_feed(reg, feed, result, today, host):
    src = reg["sources"].setdefault(feed, source_stub(feed))
    changes = []
    if result.error is not None or not result.values:
        src["status"] = "failed"
        src["error"] = (
            result.error
            or "zero rows matched (feed shape changed or all models absent)"
        )
        src["fetched_by"] = host
        return changes
    src.update(
        status="ok",
        as_of=today,
        fetched_by=host,
        error=None,
        matched=len(result.values),
    )
    for mid, vals in result.values.items():
        m = ensure_model(reg, mid)
        m["last_seen"][feed] = today
        for k, v in vals.items():
            if k in BENCH_FIELDS:
                _set(m, k, v, changes, mid)
            elif k == "pricing":
                cur = m["pricing"]
                authoritative = feed == "openrouter"
                if authoritative or cur.get("source") in (None, feed):
                    if (
                        v.get("prompt_cost_per_m") is None
                        or v.get("completion_cost_per_m") is None
                    ):
                        continue
                    if (
                        cur.get("prompt_cost_per_m"),
                        cur.get("completion_cost_per_m"),
                    ) != (v["prompt_cost_per_m"], v["completion_cost_per_m"]):
                        changes.append(
                            f"{mid}.pricing: {cur.get('prompt_cost_per_m')}/{cur.get('completion_cost_per_m')} -> {v['prompt_cost_per_m']}/{v['completion_cost_per_m']}"
                        )
                    m["pricing"] = {
                        "prompt_cost_per_m": v["prompt_cost_per_m"],
                        "completion_cost_per_m": v["completion_cost_per_m"],
                        "source": feed,
                    }
            elif k == "context_window" and v and m.get("context_window") != v:
                m["context_window"] = int(v)
            elif k == "display_name" and v and not m.get("display_name"):
                m["display_name"] = v
    return changes


def apply_overrides(reg):
    for mid, o in reg["overrides"].items():
        if o.get("track_only"):
            m = ensure_model(reg, mid)
            m["track_only"] = True
        if mid not in reg["models"]:
            continue
        m = reg["models"][mid]
        m["match"] = derive_match(mid, override=o)
        if o.get("context_window"):
            m["context_window"] = o["context_window"]
        for k, v in (o.get("benchmark_notes") or {}).items():
            m["benchmark_notes"][k] = v


# --- gates ------------------------------------------------------------------------------


def validate(reg):
    """Schema + invariants.  Returns a list of error strings (empty = valid)."""
    errs = []
    try:
        import jsonschema  # type: ignore

        with open(SCHEMA_PATH) as f:
            schema = json.load(f)
        v = jsonschema.Draft202012Validator(schema)
        for e in sorted(v.iter_errors(reg), key=lambda e: list(e.path)):
            errs.append("/".join(str(p) for p in e.path) + ": " + e.message)
    except ImportError:
        log(
            "python jsonschema not importable; schema gate skipped (invariants still checked)"
        )
    for mid, m in reg["models"].items():
        p = m.get("pricing") or {}
        for k in ("prompt_cost_per_m", "completion_cost_per_m"):
            if p.get(k) is not None and p[k] < 0:
                errs.append(f"models/{mid}/pricing/{k}: negative")
        f = m["benchmarks"].get("aa_factuality")
        if f is not None and not (0 <= f <= 1):
            errs.append(f"models/{mid}/benchmarks/aa_factuality: outside [0,1]")
    for h, host in reg["hosts"].items():
        for mid, e in host["roster"].items():
            if not e.get("is_class_entry") and mid not in reg["models"]:
                errs.append(f"hosts/{h}/roster/{mid}: no models entry")
            if e.get("pricing") and e["pricing"].get("source") != "local":
                errs.append(
                    f"hosts/{h}/roster/{mid}/pricing: only source 'local' allowed on roster entries"
                )
    return errs


def critical_ok(reg, host):
    h = reg["hosts"].get(host)
    if not h:
        return False
    return any(e.get("enabled") for e in h["roster"].values())


def write_registry(reg, path):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(reg, f, indent=2, sort_keys=True)
        f.write("\n")
    if os.path.exists(path):
        os.replace(path, path + ".bak")
    os.replace(tmp, path)


def notify(summary, body):
    env = dict(os.environ)
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{os.getuid()}/bus")
    try:
        subprocess.run(
            ["notify-send", "-a", "model-router", summary, body],
            env=env,
            check=False,
            timeout=10,
        )
    except Exception as e:  # noqa: BLE001
        log(f"notify-send unavailable ({e})")


# --- main ---------------------------------------------------------------------------------


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
    a = ap.parse_args(argv)

    if os.path.exists(a.registry):
        with open(a.registry) as f:
            reg = json.load(f)
    else:
        reg = empty_registry()
        log(f"{a.registry} absent; starting from empty registry")
    for n in list(FEEDS) + ["pi_roster", "claude_roster"]:
        reg["sources"].setdefault(n, source_stub(n))
    reg.setdefault("overrides", {})
    reg.setdefault("models", {})
    reg.setdefault("hosts", {})

    ts = now()
    today = ts[:10]
    changes = []
    old_host = reg["hosts"].get(a.host)
    old_roster = (old_host or {}).get("roster", {})

    # 1. roster
    pi_ok = os.path.exists(PI_SETTINGS) and pi_version() is not None
    pi_entries = None
    if pi_ok:
        try:
            pi_entries = pi_roster_entries(read_pi_enabled())
            reg["sources"]["pi_roster"].update(
                status="ok",
                as_of=today,
                fetched_by=a.host,
                error=None,
                matched=len(pi_entries),
            )
        except Exception as e:  # noqa: BLE001
            reg["sources"]["pi_roster"].update(
                status="failed", error=str(e), fetched_by=a.host
            )
            pi_ok = False
    else:
        reg["sources"]["pi_roster"].update(
            status="skipped", error="pi not available on this host", fetched_by=a.host
        )
    log(f"pi: {'ok' if pi_ok else 'unavailable'}")

    # 2. probe
    cv = claude_version()
    claude_ok = cv is not None
    claude_results = None
    if claude_ok and not a.no_probe:
        cands = claude_candidates(reg, a.host)
        stale = ((old_host or {}).get("probed_with") or {}).get("claude") != cv
        new_ids = [c for c in cands if c not in old_roster]
        if a.probe or stale or new_ids:
            targets = cands if (a.probe or stale) else new_ids
            log(f"claude {cv}: probing {len(targets)} candidate(s)")
            claude_results = probe_claude(targets)
            if any(v == "ok" for v in claude_results.values()):
                reg["sources"]["claude_roster"].update(
                    status="ok",
                    as_of=today,
                    fetched_by=a.host,
                    error=None,
                    matched=sum(v == "ok" for v in claude_results.values()),
                )
            else:
                reg["sources"]["claude_roster"].update(
                    status="failed",
                    error="every probe errored; prior roster kept",
                    fetched_by=a.host,
                )
                claude_results = None
        else:
            reg["sources"]["claude_roster"].update(
                status="ok", as_of=today, fetched_by=a.host, error=None
            )
            log(f"claude {cv}: roster unchanged, probe skipped")
    elif not claude_ok:
        reg["sources"]["claude_roster"].update(
            status="skipped",
            error="claude CLI not available on this host",
            fetched_by=a.host,
        )

    host = build_host(
        old_roster, pi_ok, pi_entries, claude_ok, claude_results, old_host, ts
    )
    if claude_results is not None:
        host["probed_with"]["claude"] = cv
    if pi_ok:
        host["probed_with"]["pi"] = pi_version()
    reg["hosts"][a.host] = host
    for mid, e in host["roster"].items():
        if not e.get("is_class_entry"):
            ensure_model(reg, mid)

    # 7 (early). overrides shape the match keys before feeds run
    apply_overrides(reg)

    # 3-6. feeds
    for feed in FEEDS:
        if feed in a.skip:
            reg["sources"][feed].update(
                status="skipped", error="--skip", fetched_by=a.host
            )
            continue
        try:
            result = FEED_FN[feed](reg)
        except Exception as e:  # noqa: BLE001
            result = FeedResult(error=f"{type(e).__name__}: {e}"[:300])
        c = apply_feed(reg, feed, result, today, a.host)
        st = reg["sources"][feed]
        log(
            f"{feed}: {st['status']}"
            + (
                f" ({st['error']})"
                if st.get("error")
                else f", {st.get('matched')} matched, {len(c)} change(s)"
            )
        )
        changes += c

    apply_overrides(reg)  # notes/track_only after feeds may have created entries
    reg["updated_at"] = ts

    # 8. gates
    errs = validate(reg)
    if errs:
        for e in errs[:30]:
            log(f"SCHEMA: {e}")
        log(f"GATE FAILED: {len(errs)} error(s); registry NOT written")
        return 3
    if not critical_ok(reg, a.host):
        log("GATE FAILED: host has no enabled roster entry; registry NOT written")
        return 2

    # 9. write
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
