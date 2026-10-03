"""S3 access: only GetObject/HeadObject by version and ListObjectVersions."""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from mypy_boto3_s3 import S3Client


def iso(dt: datetime) -> str:
    return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass(frozen=True)
class VEntry:
    key: str
    version_id: str
    last_modified: str
    is_latest: bool
    is_delete_marker: bool
    size: int = 0


class S3Reader:
    def __init__(self, client: S3Client, bucket: str) -> None:
        self.client = client
        self.bucket = bucket

    def head(self, key: str, version_id: str) -> tuple[str, int] | None:
        """(LastModified ISO, size) or ``None`` if the version no longer exists."""
        try:
            r = self.client.head_object(Bucket=self.bucket, Key=key, VersionId=version_id)
        except self.client.exceptions.ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"404", "NoSuchKey", "NoSuchVersion", "405", "400"}:
                return None
            raise
        return iso(r["LastModified"]), int(r["ContentLength"])

    def get(self, key: str, version_id: str) -> bytes:
        r = self.client.get_object(Bucket=self.bucket, Key=key, VersionId=version_id)
        return r["Body"].read()

    def list_entries(self, prefix: str = "", *, start_after_key: str = "") -> Iterator[VEntry]:
        """Versions and delete markers ordered by key and, within a key, newest to oldest."""
        kwargs: dict[str, Any] = {"Bucket": self.bucket, "Prefix": prefix}
        if start_after_key:
            kwargs["KeyMarker"] = start_after_key
        paginator = self.client.get_paginator("list_object_versions")
        for page in paginator.paginate(**kwargs):
            batch: list[VEntry] = []
            for v in page.get("Versions", []):
                batch.append(
                    VEntry(
                        v["Key"],
                        v["VersionId"],
                        iso(v["LastModified"]),
                        bool(v.get("IsLatest")),
                        False,
                        int(v.get("Size", 0)),
                    )
                )
            for m in page.get("DeleteMarkers", []):
                batch.append(
                    VEntry(
                        m["Key"],
                        m["VersionId"],
                        iso(m["LastModified"]),
                        bool(m.get("IsLatest")),
                        True,
                    )
                )
            batch.sort(key=lambda e: (e.key, not e.is_latest, _neg(e.last_modified)))
            yield from batch

    def entries_for_key(self, key: str) -> list[VEntry]:
        """Entries (newest → oldest) of an exact key."""
        return [e for e in self.list_entries(prefix=key) if e.key == key]


def _neg(ts: str) -> tuple[int, ...]:
    return tuple(-ord(c) for c in ts)
