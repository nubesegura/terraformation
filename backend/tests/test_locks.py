import json

from terraformation.keys import StateRef
from terraformation.locks import process_lock_event
from terraformation.store import plain
from tests.conftest import BUCKET, s3_event

KEY = "proj-a/terraform.tfstate.tflock"
REF = StateRef("proj-a", "default")


def lock_body(fixture_json, **over):
    return json.dumps({**fixture_json("lock.tflock.json"), **over}).encode()


def acquire(aws, body, key=KEY):
    return aws["s3"].put_object(Bucket=BUCKET, Key=key, Body=body)["VersionId"]


def release(aws, key=KEY):
    return aws["s3"].delete_object(Bucket=BUCKET, Key=key)["VersionId"]


def current(ctx):
    return plain(ctx.store.table.get_item(Key={"PK": REF.pk, "SK": "LOCK#CURRENT"})["Item"])


def test_lock_created_marks_locked(aws, ctx, fixture_json):
    vid = acquire(aws, lock_body(fixture_json))
    assert process_lock_event(ctx, s3_event("Object Created", KEY, vid)) == "locked"
    cur = current(ctx)
    assert cur["status"] == "LOCKED" and cur["who"] == "ana@laptop"
    assert cur["operation"] == "OperationTypeApply" and cur["lock_id"].startswith("6c1d8e6c")
    summ = plain(ctx.store.get_summary(REF))
    assert summ["lock_state"] == "locked" and summ["GSI2PK"] == "LOCKED"
    assert summ["lock_who"] == "ana@laptop"
    # does not generate state history
    assert not [i for i in aws["table"].scan()["Items"] if i["SK"].startswith("VERSION#")]


def test_lock_deleted_marks_released_and_keeps_history(aws, ctx, fixture_json):
    vid = acquire(aws, lock_body(fixture_json))
    process_lock_event(ctx, s3_event("Object Created", KEY, vid))
    marker = release(aws)
    ev = s3_event("Object Deleted", KEY, marker, **{"deletion-type": "Delete Marker Created"})
    assert process_lock_event(ctx, ev) == "released"
    assert current(ctx)["status"] == "RELEASED" and current(ctx)["who"] == "ana@laptop"
    summ = plain(ctx.store.get_summary(REF))
    assert summ["lock_state"] == "released" and "GSI2PK" not in summ
    (h,) = ctx.store.list_locks(REF)
    assert h["released_at"] is not None and h["duration_s"] >= 0


def test_duplicate_and_out_of_order_events_converge(aws, ctx, fixture_json):
    v1 = acquire(aws, lock_body(fixture_json))
    marker = release(aws)
    # the delete event arrives first and then the create one (and duplicates)
    d = s3_event("Object Deleted", KEY, marker, **{"deletion-type": "Delete Marker Created"})
    c = s3_event("Object Created", KEY, v1)
    for ev in (d, c, c, d):
        assert process_lock_event(ctx, ev) == "released"
    assert len(ctx.store.list_locks(REF)) == 1
    assert plain(ctx.store.get_summary(REF))["lock_state"] == "released"


def test_second_lock_after_release(aws, ctx, fixture_json):
    v1 = acquire(aws, lock_body(fixture_json))
    release(aws)
    v2 = acquire(aws, lock_body(fixture_json, ID="second", Who="bob@ci"))
    assert process_lock_event(ctx, s3_event("Object Created", KEY, v2)) == "locked"
    hist = {h["lock_id"]: h for h in ctx.store.list_locks(REF)}
    assert set(hist) == {"6c1d8e6c-0000-4000-8000-000000000001", "second"}
    assert hist["6c1d8e6c-0000-4000-8000-000000000001"]["released_at"]
    assert not hist["second"]["released_at"]
    assert v1 != v2
    assert current(ctx)["who"] == "bob@ci"


def test_lifecycle_permanent_delete_does_not_release(aws, ctx, fixture_json):
    old = acquire(aws, lock_body(fixture_json))
    release(aws)
    new = acquire(aws, lock_body(fixture_json, ID="active"))
    process_lock_event(ctx, s3_event("Object Created", KEY, new))
    # the old non-current version expires
    aws["s3"].delete_object(Bucket=BUCKET, Key=KEY, VersionId=old)
    ev = s3_event(
        "Object Deleted",
        KEY,
        old,
        **{"deletion-type": "Permanently Deleted", "reason": "Lifecycle Expiration"},
    )
    assert process_lock_event(ctx, ev) == "locked"
    assert current(ctx)["status"] == "LOCKED"
    assert len(ctx.store.list_locks(REF)) >= 1  # the history persists even if S3 no longer has it


def test_force_unlock_by_deleting_current_version(aws, ctx, fixture_json):
    vid = acquire(aws, lock_body(fixture_json))
    process_lock_event(ctx, s3_event("Object Created", KEY, vid))
    aws["s3"].delete_object(Bucket=BUCKET, Key=KEY, VersionId=vid)
    ev = s3_event("Object Deleted", KEY, vid, **{"deletion-type": "Permanently Deleted"})
    assert process_lock_event(ctx, ev) == "released"


def test_unreadable_lock_file_does_not_break(aws, ctx):
    vid = acquire(aws, b"not json")
    assert process_lock_event(ctx, s3_event("Object Created", KEY, vid)) == "locked"
    assert current(ctx)["who"] == "desconocido"


def test_workspace_lock_and_ignored_keys(aws, ctx, fixture_json):
    key = "env:/dev/proj-a/terraform.tfstate.tflock"
    vid = acquire(aws, lock_body(fixture_json), key)
    assert process_lock_event(ctx, s3_event("Object Created", key, vid)) == "locked"
    assert ctx.store.get_summary(StateRef("proj-a", "dev"))["lock_state"] == "locked"
    other = acquire(aws, b"{}", "proj-a/terraform.tfstate")
    assert process_lock_event(ctx, s3_event("Object Created", "proj-a/terraform.tfstate", other)) == "ignored"
