#!/usr/bin/env python3
"""Refresh ~/.agents/benchmarks.json from public feeds.

Stdlib only.  Designed to run headless from a pitchfork cron daemon:
per-source failures keep old values (log and continue), the file is
only written when a value actually changes, writes are atomic
(same-directory tmp + rename), and notify-send fires on change.

Sources and parsing rules mirror
~/.agents/skills/model-router/references/update-registry.md.
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.request

BENCH = os.path.expanduser("~/.agents/benchmarks.json")
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
TIMEOUT = 45
ELO_DRIFT = 10  # min ELO delta before an arena value updates
ELO_FIELDS = {"eq_bench_score", "design_arena_score"}
FIELD_OF = {
    "terminal_bench": "terminal_bench_score",
    "deep_swe": "deep_swe_score",
    "artificial_analysis": "artificial_analysis_index",
    "eq_bench": "eq_bench_score",
    "design_arena": "design_arena_score",
}


def log(msg):
    print(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {msg}", flush=True)


def fetch(url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers=headers or {"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read().decode("utf-8", errors="replace")


def _match_rows(model, feed_key, rows):
    """First matching feed value for a model's match list, else None."""
    for name in (model.get("match") or {}).get(feed_key, []):
        val = rows.get(name.lower())
        if val is not None:
            return val
    return None


def _match_all(reg, feed_key, rows):
    """{public_id: value} for every registry model with a feed match."""
    out = {}
    for key, model in reg["models"].items():
        val = _match_rows(model, feed_key, rows)
        if val is not None:
            out[key] = val
    return out


# --- source parsers ----------------------------------------------------------

def src_openrouter(reg):
    """{public_id: {prompt_cost_per_m, completion_cost_per_m}}"""
    raw = json.loads(fetch("https://openrouter.ai/api/v1/models"))
    by_id = {m["id"]: m for m in raw.get("data", [])}
    out = {}
    for key, model in reg["models"].items():
        orid = (model.get("match") or {}).get("openrouter")
        row = by_id.get(orid) if orid else None
        if not row:
            continue
        p = float(row["pricing"]["prompt"]) * 1e6
        c = float(row["pricing"]["completion"]) * 1e6
        if p < 0 or c < 0:  # routing-alias sentinel, not a price
            continue
        out[key] = {"prompt_cost_per_m": round(p, 6), "completion_cost_per_m": round(c, 6)}
    return out


def _flight_text(html):
    """Join and unescape Next.js flight-data chunks."""
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"((?:\\.|[^"\\])*)"\]\)', html)
    parts = []
    for ch in chunks:
        try:
            parts.append(json.loads('"' + ch + '"'))
        except ValueError:
            parts.append(ch)
    return "".join(parts)


def _tb_rows(text):
    """[(model_label, agent_label, accuracy_pct)] from flight text."""
    rows = []
    for m in re.finditer(r'"accuracy"\s*:\s*([0-9.]+)', text):
        window = text[max(0, m.start() - 2000):m.start()]
        model = re.findall(r'"model_display"\s*:\s*\{[^{}]*?"label"\s*:\s*"([^"]+)"', window)
        agent = re.findall(r'"agent_display"\s*:\s*\{[^{}]*?"label"\s*:\s*"([^"]+)"', window)
        if model:
            rows.append((model[-1], agent[-1] if agent else "?", float(m.group(1))))
    return rows


def src_terminal_bench(reg):
    """{public_id: {"score": best_pct, "agent": name}} from the primary board."""
    text = _flight_text(fetch(reg["sources"]["terminal_bench"]["url"]))
    best = {}
    for label, agent, acc in _tb_rows(text):
        cur = best.get(label.lower())
        if cur is None or acc > cur[0]:
            best[label.lower()] = (acc, agent)
    return {key: {"score": hit[0], "agent": hit[1]}
            for key, hit in _match_all(reg, "tb", best).items()}


def _first_pct(lines):
    """First 'NN%' token in lines, else None."""
    for ln in lines:
        pm = re.fullmatch(r"(\d+(?:\.\d+)?)%", ln)
        if pm:
            return float(pm.group(1))
    return None


def _deepswe_rows(text):
    """{model_slug: best pass@1 percent} from tag-stripped page text."""
    rows = {}
    lines = [ln.strip() for ln in text.split("\n") if ln.strip()]
    for i, ln in enumerate(lines):
        if not re.fullmatch(r"[a-z0-9][a-z0-9.\-]+", ln):
            continue
        val = _first_pct(lines[i + 1:i + 6])
        if val is not None and (ln not in rows or val > rows[ln]):
            rows[ln] = val
    return rows


def src_deepswe(reg):
    """{public_id: pass@1 percent} from the server-rendered v1.1 table."""
    html = fetch(reg["sources"]["deep_swe"]["url"])
    html = re.sub(r"<!--.*?-->", "", html, flags=re.S)  # comment nodes split "74%" otherwise
    text = re.sub(r"\n+", "\n", re.sub(r"<[^>]+>", "\n", html))
    return _match_all(reg, "deepswe", _deepswe_rows(text))


def _aa_via_api(reg, api_key):
    """{public_id: index int} from the keyed v2 API."""
    raw = json.loads(fetch("https://artificialanalysis.ai/api/v2/data/llms/models",
                           headers={"x-api-key": api_key, "User-Agent": UA}))
    by_slug = {m.get("slug"): m for m in raw.get("data", [])}
    out = {}
    for key, model in reg["models"].items():
        slug = (model.get("match") or {}).get("aa_slug")
        row = by_slug.get(slug)
        if not (slug and row):
            continue
        idx = row.get("evaluations", row).get("artificial_analysis_intelligence_index")
        if idx is not None:
            out[key] = round(float(idx))
    return out


def _aa_via_pages(reg):
    """{public_id: index int} scraped from per-model pages."""
    out = {}
    for key, model in reg["models"].items():
        slug = (model.get("match") or {}).get("aa_slug")
        if not slug:
            continue
        try:
            html = fetch(f"https://artificialanalysis.ai/models/{slug}")
        except Exception as e:
            log(f"aa: {slug}: fetch failed ({e})")
            continue
        m = re.search(r"scores\s+(\d+)\s+on the Artificial Analysis\s+Intelligence Index", html)
        if m:
            out[key] = int(m.group(1))
        time.sleep(1)  # be polite; 15 pages max
    if not out:
        raise RuntimeError("0 models matched; treating as source failure")
    return out


def src_artificial_analysis(reg):
    """{public_id: index int}; keyed API preferred, page scrape fallback.

    AA_API_KEY comes from the environment; the pitchfork daemon gets it
    via `fnox exec` (see ~/.config/pitchfork/config.toml).
    """
    api_key = os.environ.get("AA_API_KEY")
    if api_key:
        try:
            result = _aa_via_api(reg, api_key)
            log("aa: via keyed API")
            return result
        except Exception as e:
            log(f"aa: keyed API failed ({e}); falling back to page scrape")
    return _aa_via_pages(reg)


def src_eqbench(reg):
    """{public_id: elo} from the EQ-Bench 4 data file."""
    raw = fetch(reg["sources"]["eq_bench"]["url"])
    lines = raw.split("\n")
    if lines and lines[0].lstrip().startswith("//"):
        lines = lines[1:]
    body = re.sub(r"^const\s+\w+\s*=\s*", "", "\n".join(lines).strip()).rstrip().rstrip(";")
    rows = {}
    for m in json.loads(body).get("models", []):
        for name in (m.get("model"), m.get("display")):
            if name:
                rows[str(name).lower()] = float(m["elo"])
    return _match_all(reg, "eqbench", rows)


def src_designarena(reg):
    """{public_id: elo} from the Website arena (POST only)."""
    payload = json.dumps({"arenaType": "models", "category": "website"}).encode()
    raw = json.loads(fetch(reg["sources"]["design_arena"]["url"], data=payload,
                           headers={"Content-Type": "application/json", "User-Agent": UA}))
    rows = {str(r["modelId"]).lower(): round(float(r["elo"])) for r in raw.get("data", [])}
    return _match_all(reg, "designarena", rows)


# --- apply -------------------------------------------------------------------

def set_value(model, field, new, changes, key, note=None):
    old = model["benchmarks"].get(field) if field in model.get("benchmarks", {}) \
        else model.get("pricing", {}).get(field)
    if field in ELO_FIELDS and old is not None and abs(new - old) < ELO_DRIFT:
        return
    if old == new:
        return
    if field in ("prompt_cost_per_m", "completion_cost_per_m"):
        model.setdefault("pricing", {})[field] = new
        model["pricing"]["source"] = "openrouter"
    else:
        model["benchmarks"][field] = new
    if note:
        model.setdefault("benchmark_notes", {})[field] = note
    changes.append(f"{key}.{field}: {old} -> {new}")


def _apply_source(reg, name, result, changes):
    for key, val in result.items():
        model = reg["models"][key]
        if name == "pricing":
            for fld, v in val.items():
                set_value(model, fld, v, changes, key)
        elif name == "terminal_bench":
            pv = reg["sources"]["terminal_bench"].get("primary_version", "?")
            set_value(model, "terminal_bench_score", val["score"], changes, key,
                      note=f"TB {pv}, {val['agent']} agent (best row)")
            # a primary-version score supersedes any old-version marker
            if changes and changes[-1].startswith(f"{key}.terminal_bench_score"):
                (model.get("benchmark_versions") or {}).pop("terminal_bench_score", None)
        else:
            set_value(model, FIELD_OF[name], val, changes, key)


def notify(summary, body):
    env = dict(os.environ)
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{os.getuid()}/bus")
    try:
        subprocess.run(["notify-send", "-a", "model-router", summary, body],
                       env=env, check=False, timeout=10)
    except Exception as e:
        log(f"notify-send unavailable ({e}); change summary is in this log")


def _write_and_notify(reg, changes, fetched_ok):
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    reg["updated_at"] = now
    for name in fetched_ok:
        reg["sources"][name]["as_of"] = now[:10]
    tmp = BENCH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(reg, f, indent=2)
        f.write("\n")
    os.replace(tmp, BENCH)
    log(f"wrote {BENCH} with {len(changes)} change(s):")
    for c in changes:
        log(f"  {c}")
    notify(f"benchmarks.json: {len(changes)} change(s)",
           "\n".join(changes[:12]) + ("\n..." if len(changes) > 12 else ""))


SOURCES = [
    ("pricing", src_openrouter),
    ("terminal_bench", src_terminal_bench),
    ("deep_swe", src_deepswe),
    ("artificial_analysis", src_artificial_analysis),
    ("eq_bench", src_eqbench),
    ("design_arena", src_designarena),
]


def main():
    with open(BENCH) as f:
        reg = json.load(f)
    changes = []
    fetched_ok = []
    for name, fn in SOURCES:
        try:
            result = fn(reg)
        except Exception as e:
            log(f"{name}: FAILED ({e}); keeping old values")
            continue
        fetched_ok.append(name)
        log(f"{name}: ok, {len(result)} model(s) matched")
        _apply_source(reg, name, result, changes)
    if not changes:
        log(f"no changes ({len(fetched_ok)}/{len(SOURCES)} sources fetched); file untouched")
        return 0
    _write_and_notify(reg, changes, fetched_ok)
    return 0


if __name__ == "__main__":
    sys.exit(main())
