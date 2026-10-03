"""Access to the single DynamoDB table (see docs/DATA_MODEL.md)."""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from typing import TYPE_CHECKING, Any

from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from terraformation.keys import StateRef
from terraformation.models import Instance, StateSummary
from terraformation.parser import content_hash

if TYPE_CHECKING:
    from mypy_boto3_dynamodb.service_resource import Table

MAX_ATTRS_PER_RESOURCE = 250
MAX_ATTR_VALUE = 1024


def sort_value(last_modified: str, serial: int, version_id: str) -> str:
    """Total order of versions: LastModified, serial, versionId."""
    return f"{last_modified}#{serial:012d}#{version_id}"


def ver_sk(last_modified: str, version_id: str) -> str:
    return f"VERSION#{last_modified}#{version_id}"


def lock_sk(last_modified: str, version_id: str) -> str:
    return f"LOCK#{last_modified}#{version_id}"


def day_of(ts: str) -> str:
    return ts[:10]


def plain(value: Any) -> Any:
    """Decimal → int/float recursivamente (para respuestas JSON)."""
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value, dict):
        return {k: plain(v) for k, v in value.items()}
    if isinstance(value, list):
        return [plain(v) for v in value]
    return value


def now_iso() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_update(
    fields: dict[str, Any], remove: tuple[str, ...] = (), add: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Builds the UpdateExpression with aliases for every name (avoids reserved words)."""
    names: dict[str, str] = {}
    values: dict[str, Any] = {}
    parts: list[str] = []

    def alias(name: str) -> str:
        key = f"#a{len(names)}"
        names[key] = name
        return key

    if fields:
        sets = []
        for n, v in fields.items():
            vk = f":v{len(values)}"
            values[vk] = v
            sets.append(f"{alias(n)} = {vk}")
        parts.append("SET " + ", ".join(sets))
    if remove:
        parts.append("REMOVE " + ", ".join(alias(n) for n in remove))
    if add:
        adds = []
        for n, v in add.items():
            vk = f":v{len(values)}"
            values[vk] = v
            adds.append(f"{alias(n)} {vk}")
        parts.append("ADD " + ", ".join(adds))
    out: dict[str, Any] = {"UpdateExpression": " ".join(parts)}
    if names:
        out["ExpressionAttributeNames"] = names
    if values:
        out["ExpressionAttributeValues"] = values
    return out


class Store:
    def __init__(self, table: Table) -> None:
        self.table = table

    # ---- helpers -------------------------------------------------------------------------
    def _query_all(self, **kwargs: Any) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        while True:
            r = self.table.query(**kwargs)
            items += r["Items"]
            if "LastEvaluatedKey" not in r:
                return items
            kwargs["ExclusiveStartKey"] = r["LastEvaluatedKey"]

    def _tx(self, ops: list[dict[str, Any]]) -> None:
        """TransactWriteItems (the resource client already (de)serializes the values)."""
        prepared = [{name: {**body, "TableName": self.table.name}} for op in ops for name, body in op.items()]
        self.table.meta.client.transact_write_items(TransactItems=prepared)  # type: ignore[arg-type]

    # ---- summary -------------------------------------------------------------------------
    def get_summary(self, ref: StateRef) -> dict[str, Any] | None:
        r = self.table.get_item(Key={"PK": ref.pk, "SK": "SUMMARY"})
        return r.get("Item")

    def promote_summary(
        self,
        ref: StateRef,
        *,
        sort: str,
        version_id: str,
        last_modified: str,
        serial: int,
        lineage: str,
        terraform_version: str,
        summary: StateSummary,
        outputs: int,
    ) -> bool:
        """Marks the version as current if it is newer. ``False`` if it arrived out of order."""
        upd = build_update(
            {
                "project": ref.project,
                "workspace": ref.workspace,
                "path": ref.path,
                "current_sort": sort,
                "current_version_id": version_id,
                "last_modified": last_modified,
                "serial": serial,
                "lineage": lineage,
                "terraform_version": terraform_version,
                "resource_count": summary.resource_count,
                "by_type": summary.by_type,
                "by_provider": summary.by_provider,
                "by_module": summary.by_module,
                "outputs_count": outputs,
                "deleted": False,
                "GSI1PK": "SUMMARY",
                "GSI1SK": f"{last_modified}#{ref.sid}",
                "updated_at": now_iso(),
            },
            remove=("deleted_at",),
        )
        upd["ExpressionAttributeValues"][":sort"] = sort
        try:
            self.table.update_item(
                Key={"PK": ref.pk, "SK": "SUMMARY"},
                ConditionExpression="attribute_not_exists(current_sort) OR current_sort <= :sort",
                **upd,
            )
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return False
            raise
        return True

    def mark_deleted(self, ref: StateRef, deleted_at: str) -> None:
        self.table.update_item(
            Key={"PK": ref.pk, "SK": "SUMMARY"},
            **build_update(
                {
                    "project": ref.project,
                    "workspace": ref.workspace,
                    "path": ref.path,
                    "deleted": True,
                    "deleted_at": deleted_at,
                    "GSI1PK": "SUMMARY",
                    "GSI1SK": f"{deleted_at}#{ref.sid}",
                    "updated_at": now_iso(),
                }
            ),
        )

    def set_lock_summary(self, ref: StateRef, lock: dict[str, Any] | None, state: str) -> None:
        """Reflects the lock in the summary (``state``: locked | released)."""
        base = {"project": ref.project, "workspace": ref.workspace, "path": ref.path, "lock_state": state}
        if state == "locked" and lock:
            created = lock.get("created") or lock.get("acquired_at", "")
            upd = build_update(
                {
                    **base,
                    "lock_id": lock.get("lock_id", ""),
                    "lock_who": lock.get("who", ""),
                    "lock_operation": lock.get("operation", ""),
                    "lock_created": created,
                    "GSI2PK": "LOCKED",
                    "GSI2SK": f"{lock.get('acquired_s3', created)}#{ref.sid}",
                }
            )
        else:
            upd = build_update(
                base, remove=("GSI2PK", "GSI2SK", "lock_id", "lock_who", "lock_operation", "lock_created")
            )
        self.table.update_item(Key={"PK": ref.pk, "SK": "SUMMARY"}, **upd)

    # ---- versions ------------------------------------------------------------------------
    def list_versions(self, ref: StateRef) -> list[dict[str, Any]]:
        """All history entries ordered oldest to newest."""
        items = self._query_all(
            KeyConditionExpression=Key("PK").eq(ref.pk) & Key("SK").begins_with("VERSION#")
        )
        items.sort(key=lambda i: i["sort"])
        return items

    def version_exists(self, ref: StateRef, last_modified: str, version_id: str) -> bool:
        r = self.table.get_item(
            Key={"PK": ref.pk, "SK": ver_sk(last_modified, version_id)}, ProjectionExpression="PK"
        )
        return "Item" in r

    def put_version(self, ref: StateRef, item: dict[str, Any]) -> bool:
        """Transaction: version item (idempotent) + counters. ``False`` if it already existed."""
        lm = item["last_modified"]
        full = {"PK": ref.pk, "SK": ver_sk(lm, item["version_id"]), **item}
        day = day_of(lm)
        ops = [
            {
                "Put": {
                    "Item": full,
                    "ConditionExpression": "attribute_not_exists(PK)",
                }
            },
            {
                "Update": {
                    "Key": {"PK": ref.pk, "SK": "SUMMARY"},
                    **build_update(
                        {"project": ref.project, "workspace": ref.workspace, "path": ref.path},
                        add={"version_count": 1},
                    ),
                }
            },
            *self._activity_ops(ref, day, "versions"),
        ]
        try:
            self._tx(ops)
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "TransactionCanceledException":
                reasons = exc.response.get("CancellationReasons", [])
                if reasons and reasons[0].get("Code") == "ConditionalCheckFailed":
                    return False
            raise
        return True

    def _activity_ops(self, ref: StateRef, day: str, field: str) -> list[dict[str, Any]]:
        upd = build_update({}, add={field: 1})
        return [
            {
                "Update": {
                    "Key": {"PK": ref.pk, "SK": f"ACT#{day}"},
                    **upd,
                }
            },
            {
                "Update": {
                    "Key": {"PK": "ACTIVITY", "SK": f"DAY#{day}"},
                    **upd,
                }
            },
        ]

    def update_changes(self, ref: StateRef, sk: str, added: int, removed: int, modified: int) -> None:
        self.table.update_item(
            Key={"PK": ref.pk, "SK": sk},
            ConditionExpression="attribute_exists(PK)",
            **build_update({"added": added, "removed": removed, "modified": modified}),
        )

    def delete_item(self, ref: StateRef, sk: str) -> None:
        self.table.delete_item(Key={"PK": ref.pk, "SK": sk})
        self.table.update_item(
            Key={"PK": ref.pk, "SK": "SUMMARY"},
            **build_update({}, add={"version_count": -1}),
        )

    # ---- resources -----------------------------------------------------------------------
    def sync_resources(self, ref: StateRef, instances: list[Instance], sort: str) -> tuple[int, int]:
        """Leaves the ``RES#`` items equal to ``instances``. Returns (written, deleted)."""
        existing = {
            i["SK"]: i.get("content_hash")
            for i in self._query_all(
                KeyConditionExpression=Key("PK").eq(ref.pk) & Key("SK").begins_with("RES#"),
                ProjectionExpression="SK, content_hash",
            )
        }
        wanted: dict[str, dict[str, Any]] = {}
        for inst in instances:
            sk = f"RES#{inst.address}"
            attrs = {k: v[:MAX_ATTR_VALUE] for k, v in list(inst.attributes.items())[:MAX_ATTRS_PER_RESOURCE]}
            wanted[sk] = {
                "PK": ref.pk,
                "SK": sk,
                "project": ref.project,
                "workspace": ref.workspace,
                "path": ref.path,
                "address": inst.address,
                "type": inst.type,
                "name": inst.name,
                "module": inst.module,
                "provider": inst.provider,
                "mode": inst.mode,
                "index": inst.index or "",
                "attrs": attrs,
                "content_hash": content_hash(inst),
                "version_sort": sort,
                "GSI1PK": f"RTYPE#{inst.type}",
                "GSI1SK": f"{ref.sid}#{inst.address}",
                "GSI2PK": f"RNAME#{inst.name}",
                "GSI2SK": f"{ref.sid}#{inst.address}",
            }
        writes = deletes = 0
        with self.table.batch_writer() as bw:
            for sk, item in wanted.items():
                if existing.get(sk) != item["content_hash"]:
                    bw.put_item(Item=item)
                    writes += 1
            for sk in existing.keys() - wanted.keys():
                bw.delete_item(Key={"PK": ref.pk, "SK": sk})
                deletes += 1
        return writes, deletes

    def list_resources(self, ref: StateRef) -> list[dict[str, Any]]:
        """Resources of the current version (``RES#`` items), as stored."""
        return self._query_all(
            KeyConditionExpression=Key("PK").eq(ref.pk) & Key("SK").begins_with("RES#"),
        )

    def clear_resources(self, ref: StateRef) -> int:
        return self.sync_resources(ref, [], "")[1]

    # ---- locks ---------------------------------------------------------------------------
    def list_locks(self, ref: StateRef) -> list[dict[str, Any]]:
        items = self._query_all(KeyConditionExpression=Key("PK").eq(ref.pk) & Key("SK").begins_with("LOCK#2"))
        items.sort(key=lambda i: i["SK"])
        return items

    def put_lock_history(self, ref: StateRef, item: dict[str, Any]) -> bool:
        full = {"PK": ref.pk, "SK": lock_sk(item["acquired_s3"], item["version_id"]), **item}
        ops = [
            {"Put": {"Item": full, "ConditionExpression": "attribute_not_exists(PK)"}},
            *self._activity_ops(ref, day_of(item["acquired_s3"]), "locks"),
        ]
        try:
            self._tx(ops)
        except ClientError as exc:
            if exc.response["Error"]["Code"] == "TransactionCanceledException":
                return False
            raise
        return True

    def update_lock_release(self, ref: StateRef, sk: str, released_at: str, duration_s: int) -> None:
        self.table.update_item(
            Key={"PK": ref.pk, "SK": sk},
            **build_update({"released_at": released_at, "duration_s": duration_s}),
        )

    def put_lock_current(self, ref: StateRef, item: dict[str, Any]) -> None:
        self.table.put_item(Item={"PK": ref.pk, "SK": "LOCK#CURRENT", **item})

    # ---- lineage / plans -----------------------------------------------------------------
    def link_lineage(self, ref: StateRef, lineage: str) -> None:
        if lineage:
            self.table.put_item(
                Item={
                    "PK": f"LINEAGE#{lineage}",
                    "SK": f"STATE#{ref.sid}",
                    "project": ref.project,
                    "workspace": ref.workspace,
                    "path": ref.path,
                }
            )
