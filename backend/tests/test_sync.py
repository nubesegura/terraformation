import json

from boto3.dynamodb.conditions import Key

from terraformation.keys import StateRef
from terraformation.s3io import S3Reader
from terraformation.store import plain
from terraformation.sync import sync_bucket
from tests.conftest import BUCKET


def put(aws, key, body):
    return aws["s3"].put_object(Bucket=BUCKET, Key=key, Body=body)["VersionId"]


def populate(aws, fixture_bytes):
    put(aws, "proj-a/terraform.tfstate", fixture_bytes("tf-1.5.7-serial8.tfstate"))
    put(aws, "proj-a/terraform.tfstate", fixture_bytes("tf-1.5.7-serial9.tfstate"))
    put(aws, "env:/dev/proj-a/terraform.tfstate", fixture_bytes("tf-0.12.31.tfstate"))
    put(aws, "proj-b/terraform.tfstate", fixture_bytes("tf-0.15.5.tfstate"))
    put(aws, "proj-b/terraform.tfstate", fixture_bytes("opentofu-1.8-tf-1.9.8.tfstate"))
    put(aws, "proj-c/terraform.tfstate", fixture_bytes("unsupported-v3.tfstate"))
    put(aws, "proj-c/other.txt", b"x")
    put(aws, "terraform.tfstate", b"{}")
    lock = json.dumps(
        {"ID": "l1", "Operation": "OperationTypePlan", "Who": "x@y", "Created": "2026-01-01T00:00:00Z"}
    )
    put(aws, "proj-a/terraform.tfstate.tflock", lock.encode())
    aws["s3"].delete_object(Bucket=BUCKET, Key="proj-a/terraform.tfstate.tflock")
    put(aws, "proj-b/terraform.tfstate.tflock", lock.encode())
    # state con delete marker al final
    put(aws, "proj-d/terraform.tfstate", fixture_bytes("tf-0.12.31.tfstate"))
    aws["s3"].delete_object(Bucket=BUCKET, Key="proj-d/terraform.tfstate")


def versions(aws, ref):
    return aws["table"].query(
        KeyConditionExpression=Key("PK").eq(ref.pk) & Key("SK").begins_with("VERSION#")
    )["Items"]


def test_backfill_rebuilds_everything(aws, ctx, fixture_bytes, new_ctx):
    populate(aws, fixture_bytes)
    r = sync_bucket(ctx)
    assert r["done"] and r["stats"]["states"] == 5 and r["stats"]["locks"] == 2

    a = StateRef("proj-a", "default")
    assert len(versions(aws, a)) == 2
    assert plain(ctx.store.get_summary(a))["serial"] == 9
    assert ctx.store.get_summary(StateRef("proj-a", "dev"))["terraform_version"] == "0.12.31"
    assert ctx.store.get_summary(StateRef("proj-b", "default"))["terraform_version"] == "1.9.8"
    assert plain(ctx.store.get_summary(StateRef("proj-b", "default")))["version_count"] == 2
    # versión no soportada: se registra el error y no hay resumen vigente
    c = StateRef("proj-c", "default")
    assert versions(aws, c)[0]["parse_error"]
    # delete marker final → state eliminado
    d = ctx.store.get_summary(StateRef("proj-d", "default"))
    assert d["deleted"] is True
    # locks: historial y estados; ningún .tflock aparece como versión de state
    assert ctx.store.get_summary(a)["lock_state"] == "released"
    assert ctx.store.get_summary(StateRef("proj-b", "default"))["lock_state"] == "locked"
    for item in aws["table"].scan()["Items"]:
        if item["SK"].startswith("VERSION#"):
            assert not item["key"].endswith(".tflock")
    assert len(ctx.store.list_locks(a)) == 1


def test_backfill_is_idempotent(aws, ctx, fixture_bytes, new_ctx):
    populate(aws, fixture_bytes)
    sync_bucket(ctx)
    snapshot = sorted((i["PK"], i["SK"]) for i in aws["table"].scan()["Items"])
    counts = plain(ctx.store.get_summary(StateRef("proj-a", "default")))["version_count"]
    r = sync_bucket(new_ctx(), resync_current=True)
    assert r["done"] and r["stats"]["ingested"] == 0
    assert snapshot == sorted((i["PK"], i["SK"]) for i in aws["table"].scan()["Items"])
    assert plain(ctx.store.get_summary(StateRef("proj-a", "default")))["version_count"] == counts


def test_backfill_resumes_with_cursor(aws, ctx, fixture_bytes, new_ctx):
    populate(aws, fixture_bytes)
    cursor, loops = "", 0
    while True:
        # deadline ya vencido tras el primer key: procesa un key por tramo
        import time

        r = sync_bucket(new_ctx(), cursor=cursor, deadline=time.monotonic() - 1)
        loops += 1
        if r["done"]:
            break
        cursor = r["cursor"]
        assert loops < 50
    assert loops > 1
    assert plain(ctx.store.get_summary(StateRef("proj-a", "default")))["version_count"] == 2


def test_reconcile_repairs_missing_resources(aws, ctx, fixture_bytes, new_ctx):
    populate(aws, fixture_bytes)
    sync_bucket(ctx)
    a = StateRef("proj-a", "default")
    aws["table"].delete_item(Key={"PK": a.pk, "SK": "RES#aws_s3_bucket.logs"})
    sync_bucket(new_ctx(), resync_current=True)
    assert "Item" in aws["table"].get_item(Key={"PK": a.pk, "SK": "RES#aws_s3_bucket.logs"})


def test_entries_listing_order(aws):
    put(aws, "k/terraform.tfstate", b"1")
    put(aws, "k/terraform.tfstate", b"2")
    aws["s3"].delete_object(Bucket=BUCKET, Key="k/terraform.tfstate")
    entries = S3Reader(aws["s3"], BUCKET).entries_for_key("k/terraform.tfstate")
    assert entries[0].is_latest and entries[0].is_delete_marker and len(entries) == 3


def test_backfill_discovers_nested_states_of_each_project(aws, ctx, fixture_bytes):
    put(aws, "proj-x/network/terraform.tfstate", fixture_bytes("tf-1.5.7-serial8.tfstate"))
    put(aws, "proj-x/apps/web/prod.tfstate", fixture_bytes("tf-0.15.5.tfstate"))
    put(aws, "proj-x/db.tfstate", fixture_bytes("tf-0.12.31.tfstate"))
    put(aws, "env:/qa/proj-x/network/terraform.tfstate", fixture_bytes("tf-0.12.31.tfstate"))
    put(aws, "proj-x/notes/readme.md", b"x")
    put(aws, "proj-y/terraform.tfstate", fixture_bytes("tf-0.15.5.tfstate"))
    put(aws, "proj-x/network/terraform.tfstate.tflock", b"{}")
    r = sync_bucket(ctx)
    assert r["done"] and r["stats"]["states"] == 5 and r["stats"]["locks"] == 1
    summaries = {(s["project"], s["workspace"], s["path"]) for s in _summaries(aws)}
    assert summaries == {
        ("proj-x", "default", "network/terraform.tfstate"),
        ("proj-x", "default", "apps/web/prod.tfstate"),
        ("proj-x", "default", "db.tfstate"),
        ("proj-x", "qa", "network/terraform.tfstate"),
        ("proj-y", "default", "terraform.tfstate"),
    }
    net = StateRef("proj-x", "default", "network/terraform.tfstate")
    assert ctx.store.get_summary(net)["lock_state"] == "locked"
    assert len(versions(aws, net)) == 1


def _summaries(aws):
    return aws["table"].query(IndexName="GSI1", KeyConditionExpression=Key("GSI1PK").eq("SUMMARY"))["Items"]
