import boto3

from terraformation.ingest import finalize_key, ingest_version, process_state_event
from terraformation.keys import StateRef
from terraformation.store import plain
from tests.conftest import BUCKET, s3_event

KEY = "proj-a/terraform.tfstate"
REF = StateRef("proj-a", "default")


def put(aws, fixture_bytes, name, key=KEY):
    r = aws["s3"].put_object(Bucket=BUCKET, Key=key, Body=fixture_bytes(name))
    return r["VersionId"]


def items(aws, prefix):
    from boto3.dynamodb.conditions import Key

    return plain(
        aws["table"].query(KeyConditionExpression=Key("PK").eq(REF.pk) & Key("SK").begins_with(prefix))[
            "Items"
        ]
    )


def test_event_ingests_and_promotes(aws, ctx, fixture_bytes):
    vid = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    assert process_state_event(ctx, s3_event("Object Created", KEY, vid)) == "ingested"
    summ = plain(ctx.store.get_summary(REF))
    assert summ["current_version_id"] == vid and summ["serial"] == 8
    assert summ["resource_count"] == 5 and summ["version_count"] == 1
    assert summ["by_type"]["aws_subnet"] == 2 and summ["GSI1PK"] == "SUMMARY"
    assert len(items(aws, "RES#")) == 5
    (ver,) = items(aws, "VERSION#")
    assert ver["version_id"] == vid and ver["added"] == 5 and ver["key"] == KEY
    assert "attributes" not in ver and "body" not in ver  # never the raw state
    # no secrets in any item
    dump = str(plain(aws["table"].scan()["Items"]))
    assert "wJalr" not in dump and "hunter2" not in dump
    lineage = aws["table"].get_item(
        Key={"PK": "LINEAGE#33333333-aaaa-bbbb-cccc-000000000003", "SK": f"STATE#{REF.sid}"}
    )
    assert "Item" in lineage


def test_duplicate_event_is_idempotent(aws, ctx, fixture_bytes):
    vid = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    ev = s3_event("Object Created", KEY, vid)
    assert process_state_event(ctx, ev) == "ingested"
    assert process_state_event(ctx, ev) == "duplicate"
    summ = plain(ctx.store.get_summary(REF))
    assert summ["version_count"] == 1
    assert len(items(aws, "VERSION#")) == 1
    (day,) = items(aws, "ACT#")
    assert day["versions"] == 1


def test_second_version_counts_changes_and_updates_resources(aws, ctx, fixture_bytes):
    v8 = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    process_state_event(ctx, s3_event("Object Created", KEY, v8))
    v9 = put(aws, fixture_bytes, "tf-1.5.7-serial9.tfstate")
    process_state_event(ctx, s3_event("Object Created", KEY, v9))
    vers = items(aws, "VERSION#")
    assert len(vers) == 2
    latest = max(vers, key=lambda v: v["sort"])
    assert (latest["added"], latest["removed"], latest["modified"]) == (1, 1, 2)
    res = {r["address"] for r in items(aws, "RES#")}
    assert "aws_sns_topic.alerts" in res and 'module.net.aws_subnet.s["b"]' not in res
    assert plain(ctx.store.get_summary(REF))["current_version_id"] == v9


def test_out_of_order_does_not_override_and_fixes_successor(aws, ctx, fixture_bytes):
    v8 = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    v9 = put(aws, fixture_bytes, "tf-1.5.7-serial9.tfstate")
    # the new version (T2) arrives first and the old one (T1) afterwards
    ingest_version(ctx, REF, KEY, v9, "2026-01-02T00:00:00Z", 100)
    first = next(v for v in items(aws, "VERSION#") if v["version_id"] == v9)
    assert first["added"] == len(ctx.load(KEY, v9).instances)  # no predecessor
    ingest_version(ctx, REF, KEY, v8, "2026-01-01T00:00:00Z", 100)
    summ = plain(ctx.store.get_summary(REF))
    assert summ["current_version_id"] == v9 and summ["serial"] == 9  # no retrocede
    assert summ["version_count"] == 2
    again = next(v for v in items(aws, "VERSION#") if v["version_id"] == v9)
    assert (again["added"], again["removed"], again["modified"]) == (1, 1, 2)  # recalculado
    assert "aws_sns_topic.alerts" in {r["address"] for r in items(aws, "RES#")}


def test_same_second_ordered_by_serial(aws, ctx, fixture_bytes):
    v9 = put(aws, fixture_bytes, "tf-1.5.7-serial9.tfstate")
    v8 = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    ingest_version(ctx, REF, KEY, v8, "2026-01-01T00:00:00Z", 1)
    ingest_version(ctx, REF, KEY, v9, "2026-01-01T00:00:00Z", 1)
    assert plain(ctx.store.get_summary(REF))["serial"] == 9


def test_unparsable_state_recorded_not_promoted(aws, ctx, fixture_bytes):
    vid = put(aws, fixture_bytes, "unsupported-v3.tfstate")
    assert process_state_event(ctx, s3_event("Object Created", KEY, vid)) == "unparsable"
    (ver,) = items(aws, "VERSION#")
    assert "version=3" in ver["parse_error"]
    assert not items(aws, "RES#")
    assert "current_version_id" not in plain(ctx.store.get_summary(REF))


def test_delete_marker_and_restore(aws, ctx, fixture_bytes):
    v8 = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    process_state_event(ctx, s3_event("Object Created", KEY, v8))
    marker = aws["s3"].delete_object(Bucket=BUCKET, Key=KEY)["VersionId"]
    ev = s3_event("Object Deleted", KEY, marker, **{"deletion-type": "Delete Marker Created"})
    assert process_state_event(ctx, ev) == "deleted:deleted"
    summ = plain(ctx.store.get_summary(REF))
    assert summ["deleted"] is True and not items(aws, "RES#")
    kinds = sorted(v["kind"] for v in items(aws, "VERSION#"))
    assert kinds == ["delete_marker", "state"]
    # the duplicate event does not duplicate the marker
    process_state_event(ctx, ev)
    assert len(items(aws, "VERSION#")) == 2
    # the marker is permanently deleted → the state is current again
    aws["s3"].delete_object(Bucket=BUCKET, Key=KEY, VersionId=marker)
    ev2 = s3_event("Object Deleted", KEY, marker, **{"deletion-type": "Permanently Deleted"})
    assert process_state_event(ctx, ev2) == "deleted:promoted"
    summ = plain(ctx.store.get_summary(REF))
    assert summ["deleted"] is False and summ["current_version_id"] == v8
    assert len(items(aws, "RES#")) == 5 and len(items(aws, "VERSION#")) == 1


def test_non_state_keys_are_ignored(aws, ctx, fixture_bytes):
    r = aws["s3"].put_object(Bucket=BUCKET, Key="proj-a/terraform.tfstate.tflock", Body=b"{}")
    ev = s3_event("Object Created", "proj-a/terraform.tfstate.tflock", r["VersionId"])
    assert process_state_event(ctx, ev) == "ignored"
    assert not items(aws, "VERSION#")


def test_workspace_state(aws, ctx, fixture_bytes):
    key = "env:/dev/proj-a/terraform.tfstate"
    vid = put(aws, fixture_bytes, "tf-0.12.31.tfstate", key)
    assert process_state_event(ctx, s3_event("Object Created", key, vid)) == "ingested"
    ref = StateRef("proj-a", "dev")
    assert ctx.store.get_summary(ref)["workspace"] == "dev"
    assert ctx.store.get_summary(REF) is None


def test_finalize_force_resyncs(aws, ctx, fixture_bytes):
    vid = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    process_state_event(ctx, s3_event("Object Created", KEY, vid))
    aws["table"].delete_item(Key={"PK": REF.pk, "SK": "RES#aws_s3_bucket.logs"})
    assert len(items(aws, "RES#")) == 4
    entries = ctx.s3.entries_for_key(KEY)
    finalize_key(ctx, REF, entries, force=True)
    assert len(items(aws, "RES#")) == 5


def test_search_gsi(aws, ctx, fixture_bytes):
    from boto3.dynamodb.conditions import Key

    vid = put(aws, fixture_bytes, "tf-1.5.7-serial8.tfstate")
    process_state_event(ctx, s3_event("Object Created", KEY, vid))
    r = aws["table"].query(IndexName="GSI1", KeyConditionExpression=Key("GSI1PK").eq("RTYPE#aws_subnet"))
    assert len(r["Items"]) == 2
    r = aws["table"].query(IndexName="GSI2", KeyConditionExpression=Key("GSI2PK").eq("RNAME#logs"))
    assert r["Items"][0]["type"] == "aws_s3_bucket"
    assert boto3  # silencia import
