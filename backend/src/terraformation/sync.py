"""Full synchronization engine (backfill and reconciliation) with resume."""

from __future__ import annotations

import time
from collections.abc import Callable, Iterator
from typing import Any

from aws_lambda_powertools import Logger

from terraformation.ingest import Ctx, finalize_key, ingest_version, record_delete_marker
from terraformation.keys import parse_key, parse_lock_key
from terraformation.locks import reconcile_lock
from terraformation.models import ParsedState
from terraformation.s3io import VEntry

logger = Logger(child=True)


def _groups(entries: Iterator[VEntry]) -> Iterator[list[VEntry]]:
    current: list[VEntry] = []
    for e in entries:
        if current and current[0].key != e.key:
            yield current
            current = []
        current.append(e)
    if current:
        yield current


def sync_state_key(ctx: Ctx, entries: list[VEntry], *, resync_current: bool = False) -> dict[str, int]:
    """Registers every version of a key (oldest → newest) without repeating work."""
    ref = parse_key(entries[0].key)
    stats = {"ingested": 0, "duplicate": 0, "unparsable": 0, "markers": 0}
    if ref is None:
        return stats
    asc = list(reversed(entries))
    parsed_map: dict[str, ParsedState] = {}
    last: ParsedState | None = None
    for e in asc:
        if e.is_delete_marker:
            stats["markers"] += int(record_delete_marker(ctx, ref, e))
            continue
        status, parsed = ingest_version(
            ctx, ref, e.key, e.version_id, e.last_modified, e.size, prev_hint=last, promote=False
        )
        stats[status] += 1
        if parsed is not None:
            parsed_map[e.version_id] = parsed
            last = parsed
        elif status == "duplicate":
            last = None  # the parse of already existing versions is not kept
    finalize_key(ctx, ref, entries, parsed_map, force=resync_current)
    return stats


def sync_bucket(
    ctx: Ctx,
    *,
    cursor: str = "",
    deadline: float | None = None,
    resync_current: bool = False,
    on_key: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    """Walks the bucket. Returns ``{"done": bool, "cursor": str, "stats": {...}}``."""
    totals = {"states": 0, "locks": 0, "ingested": 0, "duplicate": 0, "unparsable": 0, "markers": 0}
    last_key = cursor
    processed = False  # at least one key per slice guarantees progress
    for group in _groups(ctx.s3.list_entries(start_after_key=cursor)):
        key = group[0].key
        if cursor and key <= cursor:
            continue  # ya procesado en un tramo anterior
        if processed and deadline is not None and time.monotonic() > deadline:
            return {"done": False, "cursor": last_key, "stats": totals}
        if parse_key(key):
            stats = sync_state_key(ctx, group, resync_current=resync_current)
            totals["states"] += 1
            for k, v in stats.items():
                totals[k] += v
        elif (lref := parse_lock_key(key)) is not None:
            reconcile_lock(ctx, lref, key, group)
            totals["locks"] += 1
        last_key = key
        processed = True
        if on_key:
            on_key(key)
    return {"done": True, "cursor": "", "stats": totals}
