import json
from datetime import date
from pathlib import Path

from terraformation.aws_map import resolver as R
from terraformation.aws_map.loader import (
    DEFAULT_PATH,
    STATE_DEGRADED,
    STATE_OK,
    STATE_UNAVAILABLE,
    load_map,
)
from terraformation.masking import MASK

TODAY = date(2026, 10, 3)

BASE = {
    "schema_version": 1,
    "reviewed_at": "2026-10-01",
    "stale_after_days": 180,
    "entries": {
        "aws_s3_bucket": {
            "role": "primary",
            "cfn_type": "AWS::S3::Bucket",
            "identity": ["id"],
            "name": ["bucket"],
            "status": "verified",
        },
        "aws_s3_bucket_policy": {
            "role": "child",
            "cfn_type": "AWS::S3::BucketPolicy",
            "parent": {"type": "aws_s3_bucket", "child_attr": "bucket", "parent_attr": ["id"]},
            "status": "verified",
        },
        "aws_lb": {
            "role": "primary",
            "cfn_type": "AWS::ElasticLoadBalancingV2::LoadBalancer",
            "identity": ["arn"],
            "status": "verified",
        },
        "aws_lb_listener": {
            "role": "child",
            "cfn_type": "AWS::ElasticLoadBalancingV2::Listener",
            "parent": {"type": "aws_lb", "child_attr": "load_balancer_arn", "parent_attr": ["arn"]},
            "status": "verified",
        },
        "aws_lb_listener_rule": {
            "role": "child",
            "parent": {"type": "aws_lb_listener", "child_attr": "listener_arn", "parent_attr": ["arn"]},
            "status": "provisional",
        },
    },
}


def write(tmp_path: Path, doc) -> Path:
    p = tmp_path / "map.json"
    p.write_text(doc if isinstance(doc, str) else json.dumps(doc), encoding="utf-8")
    return p


def item(address, tf_type, attrs, provider="registry.terraform.io/hashicorp/aws", mode="managed"):
    return {
        "address": address,
        "type": tf_type,
        "name": address.rsplit(".", 1)[-1],
        "module": "root",
        "provider": provider,
        "mode": mode,
        "attrs": attrs,
    }


def rmap(tmp_path, doc=BASE):
    return load_map(write(tmp_path, doc), today=TODAY)


# ---- cargador ----------------------------------------------------------------------------
def test_packaged_map_is_valid_and_not_stale():
    m = load_map(DEFAULT_PATH, today=date(2026, 10, 3))
    assert m.state == STATE_OK and not m.issues and not m.invalid
    assert len(m.entries) > 100
    assert m.entries["aws_s3_bucket"].cfn_type == "AWS::S3::Bucket"


def test_loader_never_raises_on_missing_or_broken_file(tmp_path):
    assert load_map(tmp_path / "nope.json").state == STATE_UNAVAILABLE
    assert load_map(write(tmp_path, "{not json")).state == STATE_UNAVAILABLE
    assert load_map(write(tmp_path, "[1,2]")).state == STATE_UNAVAILABLE
    assert load_map(write(tmp_path, {"schema_version": 99, "entries": {}})).state == STATE_UNAVAILABLE
    assert load_map(write(tmp_path, {"schema_version": 1})).state == STATE_UNAVAILABLE


def test_invalid_entries_degrade_without_losing_the_rest(tmp_path):
    doc = json.loads(json.dumps(BASE))
    doc["entries"]["aws_broken"] = {"role": "primary", "cfn_type": "not-a-type", "identity": ["id"]}
    doc["entries"]["aws_self"] = {
        "role": "child",
        "parent": {"type": "aws_self", "child_attr": "x", "parent_attr": ["id"]},
    }
    doc["entries"]["aws_noroles"] = {"cfn_type": "AWS::A::B"}
    m = rmap(tmp_path, doc)
    assert m.state == STATE_DEGRADED
    assert set(m.invalid) == {"aws_broken", "aws_self", "aws_noroles"}
    assert "aws_s3_bucket" in m.entries


def test_staleness_is_a_warning_not_an_error(tmp_path):
    doc = {**BASE, "reviewed_at": "2025-01-01"}
    m = rmap(tmp_path, doc)
    assert m.state == STATE_OK and m.stale
    assert rmap(tmp_path, {**BASE, "reviewed_at": "tomorrow"}).stale
    assert not rmap(tmp_path).stale


# ---- resolvedor: casos felices -----------------------------------------------------------
def test_children_fold_into_their_aws_resource(tmp_path):
    items = [
        item("aws_s3_bucket.logs", "aws_s3_bucket", {"id": "logs-b", "bucket": "logs-b"}),
        item("aws_s3_bucket_policy.logs", "aws_s3_bucket_policy", {"bucket": "logs-b"}),
        item("aws_s3_bucket.data", "aws_s3_bucket", {"id": "data-b", "bucket": "data-b"}),
    ]
    res = R.resolve(items, rmap(tmp_path))
    assert [(g.cfn_type, g.name) for g in res.groups] == [
        ("AWS::S3::Bucket", "data-b"),
        ("AWS::S3::Bucket", "logs-b"),
    ]
    logs = next(g for g in res.groups if g.name == "logs-b")
    assert [c.address for c in logs.components] == ["aws_s3_bucket_policy.logs"]
    assert logs.components[0].cfn_type == "AWS::S3::BucketPolicy"
    assert not res.unmapped and res.coverage()["percent"] == 100.0


def test_two_terraform_resources_can_describe_one_aws_resource(tmp_path):
    items = [
        item("aws_s3_bucket.a", "aws_s3_bucket", {"id": "same", "bucket": "same"}),
        item("module.x.aws_s3_bucket.b", "aws_s3_bucket", {"id": "same", "bucket": "same"}),
    ]
    res = R.resolve(items, rmap(tmp_path))
    assert len(res.groups) == 1 and len(res.groups[0].primaries) == 2


def test_chain_of_children_reaches_the_root(tmp_path):
    items = [
        item("aws_lb.main", "aws_lb", {"arn": "arn:lb/1"}),
        item(
            "aws_lb_listener.http", "aws_lb_listener", {"arn": "arn:lis/1", "load_balancer_arn": "arn:lb/1"}
        ),
        item("aws_lb_listener_rule.r1", "aws_lb_listener_rule", {"listener_arn": "arn:lis/1"}),
    ]
    res = R.resolve(items, rmap(tmp_path))
    assert len(res.groups) == 1 and not res.unmapped
    assert {c.address for c in res.groups[0].components} == {
        "aws_lb_listener.http",
        "aws_lb_listener_rule.r1",
    }
    assert res.groups[0].status == "provisional"  # un componente provisional contagia al grupo


def test_helpers_data_and_other_providers_are_listed_not_hidden(tmp_path):
    items = [
        item(
            "random_password.p",
            "random_password",
            {},
            provider='provider["registry.terraform.io/hashicorp/random"]',
        ),
        item("data.aws_caller_identity.me", "aws_caller_identity", {}, mode="data"),
        item(
            "cloudflare_record.x",
            "cloudflare_record",
            {},
            provider="registry.terraform.io/cloudflare/cloudflare",
        ),
    ]
    res = R.resolve(items, rmap(tmp_path))
    assert [c.address for c in res.helpers] == ["random_password.p"]
    assert [c.address for c in res.data] == ["data.aws_caller_identity.me"]
    assert [(u.address, u.reason) for u in res.unmapped] == [("cloudflare_record.x", R.NON_AWS_PROVIDER)]


# ---- resolvedor: falla segura ------------------------------------------------------------
def test_unknown_type_is_unmapped_never_guessed_by_name(tmp_path):
    # aws_s3_bucket_nuevo "looks like" a bucket, but without a rule nothing is guessed.
    res = R.resolve(
        [item("aws_s3_bucket_nuevo.x", "aws_s3_bucket_nuevo", {"id": "x", "bucket": "x"})], rmap(tmp_path)
    )
    assert not res.groups
    assert [(u.reason) for u in res.unmapped] == [R.NO_RULE]


def test_primary_without_usable_identity_is_unmapped(tmp_path):
    for attrs in ({}, {"id": ""}, {"id": MASK}):
        res = R.resolve([item("aws_s3_bucket.x", "aws_s3_bucket", attrs)], rmap(tmp_path))
        assert [u.reason for u in res.unmapped] == [R.MISSING_IDENTITY] and not res.groups


def test_orphan_child_ambiguous_parent_and_missing_ref(tmp_path):
    items = [
        item("aws_s3_bucket_policy.orphan", "aws_s3_bucket_policy", {"bucket": "nadie"}),
        item("aws_s3_bucket_policy.noref", "aws_s3_bucket_policy", {}),
        item("aws_s3_bucket.a", "aws_s3_bucket", {"id": "a1", "bucket": "dup"}),
        item("aws_s3_bucket.b", "aws_s3_bucket", {"id": "dup", "bucket": "b1"}),
        item("aws_s3_bucket_policy.amb", "aws_s3_bucket_policy", {"bucket": "dup"}),
    ]
    m = rmap(
        tmp_path,
        {
            **BASE,
            "entries": {
                **BASE["entries"],
                "aws_s3_bucket": {**BASE["entries"]["aws_s3_bucket"], "identity": ["id", "bucket"]},
                "aws_s3_bucket_policy": {
                    **BASE["entries"]["aws_s3_bucket_policy"],
                    "parent": {
                        "type": "aws_s3_bucket",
                        "child_attr": "bucket",
                        "parent_attr": ["id", "bucket"],
                    },
                },
            },
        },
    )
    res = R.resolve(items, m)
    reasons = {u.address: u.reason for u in res.unmapped}
    assert reasons["aws_s3_bucket_policy.orphan"] == R.ORPHAN_CHILD
    assert reasons["aws_s3_bucket_policy.noref"] == R.MISSING_PARENT_REF
    assert reasons["aws_s3_bucket_policy.amb"] == R.AMBIGUOUS_PARENT
    assert {g.identity for g in res.groups} == {"a1", "dup"}


def test_unavailable_map_makes_everything_unmapped(tmp_path):
    items = [
        item("aws_s3_bucket.x", "aws_s3_bucket", {"id": "x"}),
        item("random_id.r", "random_id", {}, provider="random"),
    ]
    res = R.resolve(items, load_map(tmp_path / "missing.json"))
    assert not res.groups
    assert [u.reason for u in res.unmapped] == [R.MAP_UNAVAILABLE]
    assert [c.address for c in res.helpers] == [
        "random_id.r"
    ]  # intrinsic classification, does not depend on the map
    assert res.coverage()["percent"] == 0.0


def test_invalid_entry_reports_its_reason(tmp_path):
    doc = json.loads(json.dumps(BASE))
    doc["entries"]["aws_s3_bucket"] = {"role": "primary", "cfn_type": "mal", "identity": ["id"]}
    res = R.resolve([item("aws_s3_bucket.x", "aws_s3_bucket", {"id": "x"})], rmap(tmp_path, doc))
    assert [u.reason for u in res.unmapped] == [R.INVALID_ENTRY]


def test_resolution_is_deterministic_and_total(tmp_path):
    items = [
        item("aws_s3_bucket.b", "aws_s3_bucket", {"id": "b"}),
        item("aws_s3_bucket_policy.b", "aws_s3_bucket_policy", {"bucket": "b"}),
        item("aws_unknown.u", "aws_unknown", {}),
        item("aws_s3_bucket.a", "aws_s3_bucket", {"id": "a"}),
    ]
    m = rmap(tmp_path)
    r1, r2 = R.resolve(items, m), R.resolve(list(reversed(items)), m)
    assert [g.identity for g in r1.groups] == [g.identity for g in r2.groups] == ["a", "b"]
    c = r1.coverage()
    assert c["mapped"] + c["unmapped"] == c["managed_total"] == 4 and c["unmapped_by_reason"] == {
        R.NO_RULE: 1
    }


def test_provider_short_names():
    assert R.provider_short("registry.terraform.io/hashicorp/aws") == "aws"
    assert R.provider_short('provider["registry.terraform.io/hashicorp/aws"]') == "aws"
    assert R.provider_short("provider.aws") == "aws"
    assert R.provider_short('provider["registry.terraform.io/hashicorp/aws"].use1') == "aws"
    assert R.provider_short("") == ""
