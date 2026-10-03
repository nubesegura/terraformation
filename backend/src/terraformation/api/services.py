"""API dependencies: data access, cache of parsed states, utilities."""

from __future__ import annotations

import base64
import json
from collections import OrderedDict
from datetime import UTC, datetime
from typing import Any

from boto3.dynamodb.conditions import Key
from fastapi import HTTPException

from terraformation.api.schemas import LockOut
from terraformation.config import Settings
from terraformation.keys import StateRef
from terraformation.models import ParsedState
from terraformation.parser import StateParseError, parse_state
from terraformation.s3io import S3Reader
from terraformation.store import Store, plain


def encode_cursor(key: dict[str, Any] | None) -> str | None:
    if not key:
        return None
    return base64.urlsafe_b64encode(json.dumps(key).encode()).decode()


def decode_cursor(cursor: str | None) -> dict[str, Any] | None:
    if not cursor:
        return None
    try:
        data = json.loads(base64.urlsafe_b64decode(cursor.encode()))
    except ValueError as exc:
        raise HTTPException(400, "invalid cursor") from exc
    if not isinstance(data, dict):
        raise HTTPException(400, "invalid cursor")
    return data


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=UTC)


class Services:
    """Bundles configuration, DynamoDB and S3 (replaceable in tests)."""

    def __init__(self, settings: Settings, store: Store, s3: S3Reader, bedrock: Any = None) -> None:
        self.settings = settings
        self.store = store
        self.s3 = s3
        self.bedrock = bedrock
        self._cache: OrderedDict[tuple[str, str], ParsedState] = OrderedDict()

    # ---- tiempo -----------------------------------------------------------------------------
    def now(self) -> datetime:
        return datetime.now(UTC)

    # ---- locks ------------------------------------------------------------------------------
    def lock_out(self, summary: dict[str, Any] | None, current: dict[str, Any] | None = None) -> LockOut:
        state = (summary or {}).get("lock_state")
        if state == "locked":
            s = summary or {}
            since = s.get("lock_created") or (current or {}).get("acquired_at")
            started = parse_ts(since)
            elapsed = int((self.now() - started).total_seconds()) if started else None
            threshold = self.settings.lock_alert_minutes * 60
            return LockOut(
                status="locked",
                who=s.get("lock_who", ""),
                operation=s.get("lock_operation", ""),
                lock_id=s.get("lock_id", ""),
                since=since,
                duration_s=elapsed,
                alert=elapsed is not None and elapsed > threshold,
            )
        if state == "released":
            c = current or {}
            return LockOut(
                status="released",
                who=c.get("who", ""),
                operation=c.get("operation", ""),
                lock_id=c.get("lock_id", ""),
                since=c.get("acquired_at"),
                released_at=c.get("released_at"),
            )
        return LockOut(status="none_detected")

    # ---- lecturas ---------------------------------------------------------------------------
    def summary(self, ref: StateRef) -> dict[str, Any]:
        item = self.store.get_summary(ref)
        if not item:
            raise HTTPException(404, f"proyecto no encontrado: {ref.project} ({ref.workspace})")
        return plain(item)  # type: ignore[no-any-return]

    def version_item(self, ref: StateRef, version_id: str) -> dict[str, Any]:
        if version_id in {"current", "latest"}:
            version_id = str(self.summary(ref).get("current_version_id", ""))
        for item in self.store.list_versions(ref):
            if item["version_id"] == version_id:
                return plain(item)  # type: ignore[no-any-return]
        raise HTTPException(404, f"version not found: {version_id}")

    def load_state(self, item: dict[str, Any]) -> ParsedState:
        """Downloads and parses a version from S3 (LRU of 4 states per container)."""
        if item.get("kind") != "state" or item.get("parse_error"):
            raise HTTPException(
                422,
                f"the version does not contain a readable state: {item.get('parse_error', item.get('kind'))}",
            )
        ck = (item["key"], item["version_id"])
        if ck in self._cache:
            self._cache.move_to_end(ck)
            return self._cache[ck]
        try:
            parsed = parse_state(self.s3.get(item["key"], item["version_id"]))
        except StateParseError as exc:
            raise HTTPException(422, str(exc)) from exc
        self._cache[ck] = parsed
        while len(self._cache) > 4:
            self._cache.popitem(last=False)
        return parsed

    def summaries(self) -> list[dict[str, Any]]:
        """All summaries, newest first (GSI1)."""
        items: list[dict[str, Any]] = []
        kwargs: dict[str, Any] = {
            "IndexName": "GSI1",
            "KeyConditionExpression": Key("GSI1PK").eq("SUMMARY"),
            "ScanIndexForward": False,
        }
        while True:
            r = self.store.table.query(**kwargs)
            items += r["Items"]
            if "LastEvaluatedKey" not in r:
                return [plain(i) for i in items]
            kwargs["ExclusiveStartKey"] = r["LastEvaluatedKey"]

    def activity(self, ref: StateRef, days: int = 14) -> list[int]:
        today = self.now().date()
        from datetime import timedelta

        start = (today - timedelta(days=days - 1)).isoformat()
        r = self.store.table.query(
            KeyConditionExpression=Key("PK").eq(ref.pk)
            & Key("SK").between(f"ACT#{start}", f"ACT#{today.isoformat()}~")
        )
        by_day = {str(i["SK"])[4:]: int(plain(i.get("versions", 0))) for i in r["Items"]}
        return [by_day.get((today - timedelta(days=days - 1 - n)).isoformat(), 0) for n in range(days)]
