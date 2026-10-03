"""Ingesta de versiones de .tfstate: idempotente, tolerante a duplicados y desorden."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from aws_lambda_powertools import Logger

from terraformation.config import Settings
from terraformation.diff import count_changes
from terraformation.keys import StateRef, parse_key
from terraformation.models import ParsedState
from terraformation.parser import StateParseError, parse_state, summarize
from terraformation.s3io import S3Reader, VEntry
from terraformation.store import Store, now_iso, sort_value, ver_sk

logger = Logger(child=True)


@dataclass
class Ctx:
    settings: Settings
    store: Store
    s3: S3Reader
    _cache: dict[tuple[str, str], ParsedState | None] = field(default_factory=dict)

    def load(self, key: str, version_id: str) -> ParsedState | None:
        """Descarga y parsea una versión (con caché por invocación)."""
        ck = (key, version_id)
        if ck not in self._cache:
            try:
                self._cache[ck] = parse_state(self.s3.get(key, version_id))
            except StateParseError:
                self._cache[ck] = None
        return self._cache[ck]


def _state_versions(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [i for i in items if i.get("kind") == "state" and not i.get("parse_error")]


def ingest_version(
    ctx: Ctx,
    ref: StateRef,
    key: str,
    version_id: str,
    last_modified: str,
    size: int,
    *,
    prev_hint: ParsedState | None = None,
    promote: bool = True,
) -> tuple[str, ParsedState | None]:
    """Procesa una versión. Devuelve (estado, parseado): duplicate | ingested | unparsable."""
    st = ctx.store
    if st.version_exists(ref, last_modified, version_id):
        return "duplicate", None

    base: dict[str, Any] = {
        "kind": "state",
        "version_id": version_id,
        "last_modified": last_modified,
        "size": size,
        "bucket": ctx.settings.state_bucket,
        "key": key,
        "added": 0,
        "removed": 0,
        "modified": 0,
        "resource_count": 0,
        "serial": 0,
    }
    if size > ctx.settings.max_state_bytes:
        base |= {"parse_error": "too_large", "sort": sort_value(last_modified, 0, version_id)}
        st.put_version(ref, base)
        logger.warning("state too large", key=key, size=size)
        return "unparsable", None
    try:
        parsed = parse_state(ctx.s3.get(key, version_id))
    except StateParseError as exc:
        base |= {"parse_error": str(exc)[:200], "sort": sort_value(last_modified, 0, version_id)}
        st.put_version(ref, base)
        logger.warning("unparsable state", key=key, version_id=version_id, error=str(exc))
        return "unparsable", None
    ctx._cache[(key, version_id)] = parsed

    sort = sort_value(last_modified, parsed.serial, version_id)
    items = st.list_versions(ref)
    before = [i for i in items if i["sort"] < sort]
    after = [i for i in items if i["sort"] > sort]
    pred = _state_versions(before)[-1] if _state_versions(before) else None
    succ_state = _state_versions(after)[0] if _state_versions(after) else None

    prev = prev_hint
    if prev is None and pred is not None:
        prev = ctx.load(pred["key"], pred["version_id"])
    added, removed, modified = count_changes(prev, parsed)

    summary = summarize(parsed)
    newest = not after
    if promote and newest:
        won = st.promote_summary(
            ref,
            sort=sort,
            version_id=version_id,
            last_modified=last_modified,
            serial=parsed.serial,
            lineage=parsed.lineage,
            terraform_version=parsed.terraform_version,
            summary=summary,
            outputs=len(parsed.outputs),
        )
        if won:
            st.sync_resources(ref, parsed.instances, sort)
            st.link_lineage(ref, parsed.lineage)

    if succ_state is not None:  # llegó fuera de orden: el sucesor cambia de base de comparación
        succ_parsed = ctx.load(succ_state["key"], succ_state["version_id"])
        if succ_parsed is not None:
            a, r, m = count_changes(parsed, succ_parsed)
            st.update_changes(ref, succ_state["SK"], a, r, m)

    item = base | {
        "sort": sort,
        "serial": parsed.serial,
        "lineage": parsed.lineage,
        "terraform_version": parsed.terraform_version,
        "resource_count": summary.resource_count,
        "added": added,
        "removed": removed,
        "modified": modified,
    }
    st.put_version(ref, item)
    return "ingested", parsed


def record_delete_marker(ctx: Ctx, ref: StateRef, entry: VEntry) -> bool:
    if ctx.store.version_exists(ref, entry.last_modified, entry.version_id):
        return False
    return ctx.store.put_version(
        ref,
        {
            "kind": "delete_marker",
            "version_id": entry.version_id,
            "last_modified": entry.last_modified,
            "sort": sort_value(entry.last_modified, 0, entry.version_id),
            "bucket": ctx.settings.state_bucket,
            "key": entry.key,
            "serial": 0,
            "resource_count": 0,
            "added": 0,
            "removed": 0,
            "modified": 0,
        },
    )


def finalize_key(
    ctx: Ctx,
    ref: StateRef,
    entries: list[VEntry],
    parsed_by_version: dict[str, ParsedState] | None = None,
    *,
    force: bool = False,
) -> str:
    """Alinea el resumen con la realidad de S3 (``entries``: nuevo → antiguo)."""
    st = ctx.store
    latest = next((e for e in entries if e.is_latest), entries[0] if entries else None)
    if latest is None:
        return "empty"
    if latest.is_delete_marker:
        record_delete_marker(ctx, ref, latest)
        summ = st.get_summary(ref) or {}
        if not summ.get("deleted") or force:
            st.mark_deleted(ref, latest.last_modified)
            st.clear_resources(ref)
        return "deleted"
    summ = st.get_summary(ref) or {}
    if not force and summ.get("current_version_id") == latest.version_id and not summ.get("deleted"):
        return "current"
    parsed = (parsed_by_version or {}).get(latest.version_id) or ctx.load(latest.key, latest.version_id)
    if parsed is None:
        return "unparsable"
    sort = sort_value(latest.last_modified, parsed.serial, latest.version_id)
    summary = summarize(parsed)
    won = st.promote_summary(
        ref,
        sort=sort,
        version_id=latest.version_id,
        last_modified=latest.last_modified,
        serial=parsed.serial,
        lineage=parsed.lineage,
        terraform_version=parsed.terraform_version,
        summary=summary,
        outputs=len(parsed.outputs),
    )
    if won or force:
        st.sync_resources(ref, parsed.instances, sort)
        st.link_lineage(ref, parsed.lineage)
    return "promoted"


def remove_version(ctx: Ctx, ref: StateRef, version_id: str) -> bool:
    """Elimina del historial una versión borrada permanentemente de S3."""
    for item in ctx.store.list_versions(ref):
        if item["version_id"] == version_id:
            ctx.store.delete_item(ref, item["SK"])
            return True
    return False


def process_state_event(ctx: Ctx, event: dict[str, Any]) -> str:
    """Procesa un evento ``Object Created`` / ``Object Deleted`` de EventBridge."""
    detail = event.get("detail", {})
    key = detail.get("object", {}).get("key", "")
    version_id = detail.get("object", {}).get("version-id") or ""
    ref = parse_key(key)
    if ref is None:
        logger.info("ignored key", key=key)
        return "ignored"
    kind = event.get("detail-type")
    if kind == "Object Created":
        head = ctx.s3.head(key, version_id) if version_id else None
        if head is None:
            logger.warning("version not found", key=key, version_id=version_id)
            return "missing"
        status, _ = ingest_version(ctx, ref, key, version_id, head[0], head[1])
        if status == "duplicate":
            logger.info("duplicate event", key=key, version_id=version_id)
        return status
    if kind == "Object Deleted":
        if detail.get("deletion-type") == "Permanently Deleted" and version_id:
            remove_version(ctx, ref, version_id)
        entries = ctx.s3.entries_for_key(key)
        return "deleted:" + finalize_key(ctx, ref, entries, force=False)
    logger.warning("unexpected detail-type", detail_type=kind)
    return "ignored"


__all__ = [
    "Ctx",
    "finalize_key",
    "ingest_version",
    "now_iso",
    "process_state_event",
    "record_delete_marker",
    "remove_version",
    "ver_sk",
]
