#!/usr/bin/env python3
"""Pure parsers for the non-AA leaderboards.  No I/O; FETCH only describes it.

Every parser returns rows ``{"key", "score", "ci", "effort", "votes"}`` and
raises ``MinRowsError`` when it sees fewer rows than ``MIN_ROWS[board]``.

Provenance (2026-11-09): the sandbox denies arena.ai, designarena.ai,
eqbench.com, and datasets-server.huggingface.co, so the Arena row schema is
read from the dataset card (README features) and the Design Arena and
EQ-Bench shapes come from the v3 parsers.  Arena category values and row
counts were confirmed on 2026-11-09 through the /statistics endpoint.

MathArena has no machine-readable leaderboard: eth-sri/matharena is the app
source, and the MathArena/* Hugging Face datasets hold per-problem outputs
only.  The board is deliberately absent.
"""

import json
import re
from collections.abc import Iterable, Mapping, Sequence
from typing import Any, Final

Row = dict[str, Any]

EFFORTS: Final = ("off", "minimal", "low", "medium", "high", "xhigh", "max")
ARENA_LANGS: Final = (
    "chinese",
    "korean",
    "french",
    "german",
    "spanish",
    "japanese",
    "russian",
    "polish",
)
ARENA_EUROPEAN: Final = ("french", "german", "spanish", "polish", "russian")
ARENA_LANG_MIN: Final = 5

# board -> (config, category).  Category values confirmed 2026-11-09 via the
# datasets-server /statistics endpoint.  The webdev config mixes five
# categories (webdev, overall, webdev-html, webdev-react, image_to_webdev),
# so it must be filtered too.  A wrong name yields zero rows -> MinRowsError.
ARENA_CATEGORY: Final[dict[str, tuple[str, str | None]]] = {
    "arena_webdev": ("webdev", "webdev"),
    "arena_creative_writing": ("text", "creative_writing"),
    **{f"arena_{lang}": ("text", lang) for lang in ARENA_LANGS},
}

# About 60% of the rows seen on 2026-11-09 (text/latest: chinese 394, korean
# 288, french 300, german 320, spanish 303, japanese 288, russian 384, polish
# 244, creative_writing 418; webdev/latest category webdev 153).  The Design
# Arena count was never observed: a conservative estimate.  EQ-Bench is 75%
# of the 32 rows the first live refresh saw (2026-11-10).
MIN_ROWS: Final[dict[str, int]] = {
    "arena_webdev": 90,
    "arena_creative_writing": 250,
    "arena_chinese": 236,
    "arena_korean": 170,
    "arena_french": 180,
    "arena_german": 190,
    "arena_spanish": 180,
    "arena_japanese": 170,
    "arena_russian": 230,
    "arena_polish": 145,
    "design_arena": 40,
    "eq_bench": 24,
}

# /rows reads the cached parquet; /filter queries a DuckDB index the server
# builds on demand, and returned HTTP 500, 502, or timeouts on 2026-11-10.
# /rows cannot filter, so boards on one config share one URL (one fetch per
# run), and the parsers filter by category.
_HF = "https://datasets-server.huggingface.co/rows"
_DATASET = "dataset=lmarena-ai/leaderboard-dataset&split=latest"


def _arena_fetch(board: str) -> dict[str, str | None]:
    config, _ = ARENA_CATEGORY[board]
    return {
        "url": f"{_HF}?{_DATASET}&config={config}",
        "method": "GET",
        "body": None,
        "paging": "append &offset=N&length=100 until rows is empty",
    }


FETCH: Final[dict[str, dict[str, str | None]]] = {
    **{b: _arena_fetch(b) for b in ARENA_CATEGORY},
    "design_arena": {
        "url": "https://www.designarena.ai/api/leaderboard",
        "method": "POST",
        "body": '{"arenaType":"models","category":"website"}',
        "paging": None,
    },
    "eq_bench": {
        "url": "https://eqbench.com/eqbench4/eqbench4_data.js",
        "method": "GET",
        "body": None,
        "paging": None,
    },
}


class MinRowsError(Exception):
    """A parser saw fewer rows than its row minimum."""


def _check(board: str, rows: list[Row], min_rows: int | None) -> list[Row]:
    need = MIN_ROWS[board] if min_rows is None else min_rows
    if len(rows) < need:
        raise MinRowsError(f"{board}: {len(rows)} rows, minimum {need}")
    return rows


def _decode(raw: bytes | str | Any) -> Any:
    if isinstance(raw, bytes | str):
        return json.loads(raw)
    return raw


_EFFORT_RE = re.compile(r"\s*\((" + "|".join(EFFORTS) + r")\)\s*$", re.IGNORECASE)


def split_effort(name: str) -> tuple[str, str | None]:
    """Split a trailing ``(High)`` style suffix off a display name."""
    m = _EFFORT_RE.search(name)
    if m is None:
        return name.strip().lower(), None
    return name[: m.start()].strip().lower(), m.group(1).lower()


def _arena_rows(page: Mapping[str, Any], category: str | None) -> Iterable[Row]:
    for item in page.get("rows", []):
        r = item.get("row", item)
        if r.get("rating") is None or not r.get("model_name"):
            continue
        if category is not None and r.get("category") != category:
            continue
        key, effort = split_effort(r["model_name"])
        lo, hi = r.get("rating_lower"), r.get("rating_upper")
        votes = r.get("vote_count")
        yield {
            "key": key,
            "score": float(r["rating"]),
            "ci": (hi - lo) / 2 if lo is not None and hi is not None else None,
            "effort": effort,
            "votes": int(votes) if votes is not None else None,
        }


def parse_arena(raw: Any, board: str, *, min_rows: int | None = None) -> list[Row]:
    """Parse datasets-server page(s) for one Arena board.

    ``raw`` is bytes, str, one decoded page, or a list of pages.
    """
    _, category = ARENA_CATEGORY[board]
    data = _decode(raw)
    pages = data if isinstance(data, list) else [data]
    seen: dict[tuple[str, str | None], Row] = {}
    for page in pages:
        for r in _arena_rows(_decode(page), category):
            seen.setdefault((r["key"], r["effort"]), r)
    return _check(board, list(seen.values()), min_rows)


def parse_arena_webdev(raw: Any, *, min_rows: int | None = None) -> list[Row]:
    return parse_arena(raw, "arena_webdev", min_rows=min_rows)


def parse_arena_creative_writing(raw: Any, *, min_rows: int | None = None) -> list[Row]:
    return parse_arena(raw, "arena_creative_writing", min_rows=min_rows)


def parse_arena_chinese(raw: Any, *, min_rows: int | None = None) -> list[Row]:
    return parse_arena(raw, "arena_chinese", min_rows=min_rows)


def parse_arena_japanese(raw: Any, *, min_rows: int | None = None) -> list[Row]:
    return parse_arena(raw, "arena_japanese", min_rows=min_rows)


def _mean(
    by_board: Mapping[str, Sequence[Row]], langs: Sequence[str], need: int
) -> list[Row]:
    groups: dict[tuple[str, str | None], list[Row]] = {}
    for lang in langs:
        for r in by_board.get("arena_" + lang, ()):
            groups.setdefault((r["key"], r["effort"]), []).append(r)
    out: list[Row] = []
    for (key, effort), rs in groups.items():
        if len(rs) < need:
            continue
        votes = [r["votes"] for r in rs if r["votes"] is not None]
        out.append(
            {
                "key": key,
                "score": sum(r["score"] for r in rs) / len(rs),
                "ci": None,
                "effort": effort,
                "votes": sum(votes) if votes else None,
            }
        )
    return out


def arena_lang_mean(by_board: Mapping[str, Sequence[Row]]) -> list[Row]:
    """Mean over the 8 language boards; a model needs at least 5 of them."""
    return _mean(by_board, ARENA_LANGS, ARENA_LANG_MIN)


def arena_european_mean(by_board: Mapping[str, Sequence[Row]]) -> list[Row]:
    """Mean over French, German, Spanish, Polish, and Russian; all five."""
    return _mean(by_board, ARENA_EUROPEAN, len(ARENA_EUROPEAN))


def _elo_rows(items: Iterable[tuple[str, Any]]) -> list[Row]:
    return [
        {"key": k.lower(), "score": float(v), "ci": None, "effort": None, "votes": None}
        for k, v in items
        if v is not None
    ]


def parse_designarena(raw: Any, *, min_rows: int | None = None) -> list[Row]:
    """Design Arena ``.data[] {modelId, elo}``."""
    data = _decode(raw)
    rows = _elo_rows((r["modelId"], r.get("elo")) for r in data.get("data", []))
    return _check("design_arena", rows, min_rows)


def parse_eqbench(raw: bytes | str, *, min_rows: int | None = None) -> list[Row]:
    """EQ-Bench 4 JS: ``const X = {...};`` with ``.models[] {model, elo}``."""
    js = raw.decode() if isinstance(raw, bytes) else raw
    body = re.sub(r"^\s*//[^\n]*\n", "", js, count=1)
    body = re.sub(r"^\s*const\s+\w+\s*=\s*", "", body).rstrip().rstrip(";")
    data = json.loads(body)
    rows = _elo_rows((m["model"], m.get("elo")) for m in data.get("models", []))
    return _check("eq_bench", rows, min_rows)
