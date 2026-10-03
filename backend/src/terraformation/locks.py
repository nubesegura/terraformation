"""Rebuilds the locking state from the .tflock versions in S3.

Events only *trigger* the process; the truth is ``ListObjectVersions`` (D13):
a newer version ⇒ locked, a newer delete marker ⇒ released.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

from aws_lambda_powertools import Logger

from terraformation.ingest import Ctx
from terraformation.keys import StateRef, parse_lock_key
from terraformation.models import LockInfo
from terraformation.s3io import VEntry
from terraformation.store import lock_sk, now_iso

logger = Logger(child=True)


def _ts(iso_s: str) -> datetime:
    return datetime.strptime(iso_s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)


def read_lock(ctx: Ctx, key: str, version_id: str) -> LockInfo:
    try:
        return LockInfo.model_validate(json.loads(ctx.s3.get(key, version_id)))
    except (ValueError, TypeError):
        logger.warning("unreadable lock file", key=key, version_id=version_id)
        return LockInfo(Who="desconocido")


def reconcile_lock(
    ctx: Ctx, ref: StateRef, key: str, entries: list[VEntry], *, event_time: str | None = None
) -> str:
    """``entries``: entries of the key (newest → oldest). Returns locked | released | none."""
    st = ctx.store
    asc = list(reversed(entries))
    history = {h["version_id"]: h for h in st.list_locks(ref)}
    last_item: dict[str, Any] | None = None

    for i, entry in enumerate(asc):
        if entry.is_delete_marker:
            continue
        released = asc[i + 1].last_modified if i + 1 < len(asc) else None
        item = history.get(entry.version_id)
        if item is None:
            info = read_lock(ctx, key, entry.version_id)
            item = {
                "version_id": entry.version_id,
                "acquired_s3": entry.last_modified,
                "acquired_at": info.created or entry.last_modified,
                "lock_id": info.id,
                "operation": info.operation,
                "who": info.who,
                "version": info.version,
                "path": info.path,
                "info": info.info,
                "released_at": None,
            }
            st.put_lock_history(ref, item)
            item = {"PK": ref.pk, "SK": lock_sk(entry.last_modified, entry.version_id), **item}
        if released and item.get("released_at") != released:
            duration = int((_ts(released) - _ts(entry.last_modified)).total_seconds())
            st.update_lock_release(ref, item["SK"], released, max(duration, 0))
            item = {**item, "released_at": released, "duration_s": max(duration, 0)}
        last_item = item

    latest = next((e for e in entries if e.is_latest), entries[0] if entries else None)
    if latest is None:
        # No object is left: if there was an active lock, it was released (e.g. version deleted).
        prev = st.table.get_item(Key={"PK": ref.pk, "SK": "LOCK#CURRENT"}).get("Item")
        if not prev:
            return "none"
        released_at = event_time or now_iso()
        st.put_lock_current(ref, {**_strip(prev), "status": "RELEASED", "released_at": released_at})
        st.set_lock_summary(ref, None, "released")
        return "released"

    if latest.is_delete_marker:
        base = _strip(last_item) if last_item else {}
        st.put_lock_current(ref, {**base, "status": "RELEASED", "released_at": latest.last_modified})
        st.set_lock_summary(ref, None, "released")
        return "released"

    assert last_item is not None
    current = {**_strip(last_item), "status": "LOCKED", "released_at": None}
    st.put_lock_current(ref, current)
    st.set_lock_summary(ref, current, "locked")
    return "locked"


def _strip(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in {"PK", "SK"}}


def process_lock_event(ctx: Ctx, event: dict[str, Any]) -> str:
    detail = event.get("detail", {})
    key = detail.get("object", {}).get("key", "")
    ref = parse_lock_key(key)
    if ref is None:
        logger.info("ignored lock key", key=key)
        return "ignored"
    if detail.get("deletion-type") == "Permanently Deleted":
        logger.info("permanent delete (lifecycle or manual)", key=key, reason=detail.get("reason"))
    entries = ctx.s3.entries_for_key(key)
    return reconcile_lock(
        ctx,
        ref,
        key,
        entries,
        event_time=(event.get("time") or "")[:19] + "Z" if event.get("time") else None,
    )
