import json
from datetime import UTC, datetime
from unittest.mock import MagicMock

import pytest
import yaml
from fastapi.testclient import TestClient
from openapi_spec_validator import validate

from terraformation.api.app import create_app, set_services
from terraformation.api.services import Services
from terraformation.ingest import ingest_version, process_state_event
from terraformation.keys import StateRef
from terraformation.locks import process_lock_event
from tests.conftest import BUCKET, s3_event

REF = StateRef("proj-a", "default")
KEY = "proj-a/terraform.tfstate"


@pytest.fixture
def versions(aws, ctx, fixture_bytes):
    ids = {}
    for name, lm in (
        ("tf-1.5.7-serial8.tfstate", "2026-01-01T00:00:00Z"),
        ("tf-1.5.7-serial9.tfstate", "2026-01-02T00:00:00Z"),
    ):
        vid = aws["s3"].put_object(Bucket=BUCKET, Key=KEY, Body=fixture_bytes(name))["VersionId"]
        ingest_version(ctx, REF, KEY, vid, lm, 100)
        ids[name] = vid
    other = "proj-b/terraform.tfstate"
    vid = aws["s3"].put_object(Bucket=BUCKET, Key=other, Body=fixture_bytes("tf-0.15.5.tfstate"))["VersionId"]
    ingest_version(ctx, StateRef("proj-b", "default"), other, vid, "2026-01-03T00:00:00Z", 100)
    return ids


@pytest.fixture
def svc(ctx, settings, versions):
    s = Services(settings, ctx.store, ctx.s3)
    s.now = lambda: datetime(2026, 1, 15, 10, 10, tzinfo=UTC)  # type: ignore[method-assign]
    set_services(s)
    return s


@pytest.fixture
def client(svc):
    return TestClient(create_app("all"))


def lock(aws, ctx, fixture_json, key="proj-a/terraform.tfstate.tflock", **over):
    body = json.dumps({**fixture_json("lock.tflock.json"), **over}).encode()
    vid = aws["s3"].put_object(Bucket=BUCKET, Key=key, Body=body)["VersionId"]
    process_lock_event(ctx, s3_event("Object Created", key, vid))


def test_projects_sorted_by_last_modified_with_activity(client):
    r = client.get("/api/projects").json()
    assert [p["project"] for p in r["items"]] == ["proj-b", "proj-a"]
    a = r["items"][1]
    assert a["serial"] == 9 and a["version_count"] == 2 and a["lock"]["status"] == "none_detected"
    assert len(a["activity"]) == 14
    assert client.get("/api/projects", params={"q": "proj-a"}).json()["items"][0]["project"] == "proj-a"


def test_project_detail_and_404(client):
    assert client.get("/api/projects/proj-a").json()["resource_count"] == 5
    r = client.get("/api/projects/nope")
    assert r.status_code == 404 and "detail" in r.json()


def test_versions_and_timeline(client, aws, ctx, fixture_json):
    lock(aws, ctx, fixture_json)
    v = client.get("/api/projects/proj-a/versions").json()["items"]
    assert [x["serial"] for x in v] == [9, 8] and v[0]["is_current"] and v[0]["modified"] == 2
    t = client.get("/api/projects/proj-a/timeline").json()["items"]
    assert {e["type"] for e in t} == {"version", "lock_acquired"}


def test_state_detail_masks_and_reads_from_s3(client, versions):
    vid = versions["tf-1.5.7-serial8.tfstate"]
    r = client.get(f"/api/projects/proj-a/versions/{vid}").json()
    assert r["info"]["serial"] == 8 and r["info"]["s3_key"] == KEY
    assert {m["path"] for m in r["modules"]} == {"root", "module.net"}
    text = json.dumps(r)
    assert "wJalr" not in text and "AKIAABCDEFGHIJKLMNOP" not in text
    cur = client.get("/api/projects/proj-a/versions/current").json()
    assert cur["info"]["serial"] == 9
    assert client.get("/api/projects/proj-a/versions/zzz").status_code == 404


def test_diff_endpoint(client, versions):
    r = client.get(
        "/api/projects/proj-a/diff",
        params={"from_version": versions["tf-1.5.7-serial8.tfstate"], "to_version": "current"},
    ).json()
    assert r["summary"] == {"added": 1, "removed": 1, "modified": 2, "unchanged": 2}
    assert r["from"]["serial"] == 8 and r["to"]["serial"] == 9
    assert any(m["unified_diff"] for m in r["modified"])


def test_graph_endpoint(client):
    g = client.get("/api/projects/proj-a/graph").json()
    assert any(e["target"] == "module.net" for e in g["edges"]) and g["module_edges"]


def test_locks_states_and_alert(client, aws, ctx, fixture_json):
    lock(aws, ctx, fixture_json)  # Created 10:00, now 10:10 → no alert
    r = client.get("/api/locks").json()
    assert r["threshold_minutes"] == 30 and len(r["items"]) == 1
    assert r["items"][0]["who"] == "ana@laptop" and r["items"][0]["alert"] is False
    assert client.get("/api/projects/proj-a").json()["lock"]["status"] == "locked"
    # 31+ minutes later → alert
    client.app  # noqa: B018
    from terraformation.api.app import get_services

    get_services().now = lambda: datetime(2026, 1, 15, 10, 45, tzinfo=UTC)  # type: ignore[method-assign]
    assert client.get("/api/locks").json()["items"][0]["alert"] is True
    d = client.get("/api/dashboard").json()
    assert d["locked"] == 1 and d["lock_alerts"] == 1
    h = client.get("/api/projects/proj-a/locks").json()
    assert h["current"]["status"] == "locked" and h["items"][0]["active"] and h["items"][0]["alert"]


def test_released_status(client, aws, ctx, fixture_json):
    lock(aws, ctx, fixture_json)
    aws["s3"].delete_object(Bucket=BUCKET, Key="proj-a/terraform.tfstate.tflock")
    process_lock_event(ctx, s3_event("Object Deleted", "proj-a/terraform.tfstate.tflock", "m"))
    p = client.get("/api/projects/proj-a").json()
    assert p["lock"]["status"] == "released" and p["lock"]["who"] == "ana@laptop"
    assert client.get("/api/locks").json()["items"] == []


def test_dashboard_and_facets(client):
    d = client.get("/api/dashboard").json()
    assert d["projects"] == 2 and d["resources"] == 5 + 3
    assert d["by_provider"]["hashicorp/aws"] >= 5 and set(d["terraform_versions"]) == {"1.5.7", "0.15.5"}
    assert len(d["activity"]) == 30 and len(d["recent"]) == 2
    f = client.get("/api/facets").json()
    assert "aws_subnet" in f["resource_types"] and f["projects"] == ["proj-a", "proj-b"]


def test_search_variants(client):
    by_type = client.get("/api/search", params={"type": "aws_subnet"}).json()["items"]
    assert len(by_type) == 1 and by_type[0]["module"] == "module.net"
    assert client.get("/api/search", params={"type": "aws_subnet", "project": "proj-b"}).json()["items"] == []
    by_name = client.get("/api/search", params={"name": "logs"}).json()["items"]
    assert [h["type"] for h in by_name] == ["aws_s3_bucket"]
    by_proj = client.get("/api/search", params={"project": "proj-a", "workspace": "default"}).json()["items"]
    assert len(by_proj) == 5
    by_module = client.get("/api/search", params={"type": "aws_subnet", "module": "net"}).json()["items"]
    assert len(by_module) == 1
    root_only = client.get(
        "/api/search", params={"project": "proj-a", "workspace": "default", "module": "root"}
    ).json()["items"]
    assert len(root_only) == 3
    scan = client.get(
        "/api/search", params={"attribute_key": "cidr_block", "attribute_value": "10.0.2"}
    ).json()["items"]
    assert [h["address"] for h in scan] == []  # subnet b is no longer in the current version
    scan = client.get(
        "/api/search", params={"attribute_key": "cidr_block", "attribute_value": "10.0.1"}
    ).json()["items"]
    assert [h["attributes"] for h in scan] == [{"cidr_block": "10.0.1.0/24"}]


def test_secrets_never_searchable(client):
    assert client.get("/api/search", params={"attribute_value": "hunter2"}).json()["items"] == []
    assert client.get("/api/search", params={"attribute_value": "wJalr"}).json()["items"] == []


def test_bedrock_disabled_and_enabled(client, svc, versions):
    body = {"from_version": versions["tf-1.5.7-serial8.tfstate"], "to_version": "current"}
    r = client.post("/api/projects/proj-a/diff/summary", json=body)
    assert r.status_code == 501
    fake = MagicMock()
    fake.converse.return_value = {"output": {"message": {"content": [{"text": "An SNS topic was added."}]}}}
    svc.bedrock = fake
    svc.settings = svc.settings.model_copy(update={"enable_bedrock": True, "bedrock_model_id": "model-x"})
    r = client.post("/api/projects/proj-a/diff/summary", json=body).json()
    assert r["summary"].startswith("An SNS") and r["model_id"] == "model-x"
    prompt = fake.converse.call_args.kwargs["messages"][0]["content"][0]["text"]
    assert "aws_sns_topic.alerts" in prompt and "zzzz" not in prompt and "wJalr" not in prompt


PLAN = {
    "terraform_version": "1.9.0",
    "resource_changes": [
        {"address": "aws_s3_bucket.a", "type": "aws_s3_bucket", "change": {"actions": ["create"]}},
        {"address": "aws_s3_bucket.b", "type": "aws_s3_bucket", "change": {"actions": ["delete", "create"]}},
        {"address": "aws_s3_bucket.c", "type": "aws_s3_bucket", "change": {"actions": ["no-op"]}},
    ],
    "output_changes": {"o": {"actions": ["update"]}},
    "configuration": {
        "provider_config": {
            "aws": {"full_name": "registry.terraform.io/hashicorp/aws", "version_constraint": "~> 5.0"}
        }
    },
}


def test_plans_submit_and_read(client):
    payload = {
        "lineage": "33333333-aaaa-bbbb-cccc-000000000003",
        "terraform_version": "1.9.0",
        "git_remote": "https://git.example/x.git",
        "git_commit": "abc123",
        "ci_url": "https://ci.example/1",
        "source": "ci",
        "plan_json": PLAN,
    }
    r = client.post("/api/plans", json=payload)
    assert r.status_code == 201
    body = r.json()
    assert body["counts"] == {"create": 1, "replace": 1, "no-op": 1} and body["exit_code"] == 2
    listing = client.get("/api/plans", params={"project": "proj-a"}).json()["items"]
    assert len(listing) == 1 and listing[0]["git_commit"] == "abc123"
    d = client.get(f"/api/plans/{payload['lineage']}/{body['id']}").json()
    assert [x["address"] for x in d["resources"]] == ["aws_s3_bucket.a", "aws_s3_bucket.b"]
    assert d["provider_constraints"] == {"registry.terraform.io/hashicorp/aws": "~> 5.0"}
    assert "plan_json" not in json.dumps(d)
    assert client.get("/api/plans").status_code == 400


def test_app_modes_separate_routes(svc):
    main, plans = TestClient(create_app("main")), TestClient(create_app("plans"))
    assert main.post("/api/plans", json={"lineage": "x"}).status_code in {404, 405}
    assert plans.get("/api/projects").status_code == 404
    assert plans.post("/api/plans", json={"lineage": "x"}).status_code == 201


def test_mangum_http_api_v2_event(svc, monkeypatch):
    from terraformation.handlers import api as api_handler

    monkeypatch.setattr(api_handler, "get_services", lambda: svc)
    event = {
        "version": "2.0",
        "routeKey": "ANY /api/{proxy+}",
        "rawPath": "/api/projects",
        "rawQueryString": "q=proj-a",
        "headers": {"host": "x.execute-api.us-east-1.amazonaws.com", "accept": "application/json"},
        "requestContext": {
            "accountId": "000000000000",
            "apiId": "x",
            "domainName": "x.execute-api.us-east-1.amazonaws.com",
            "http": {
                "method": "GET",
                "path": "/api/projects",
                "protocol": "HTTP/1.1",
                "sourceIp": "1.2.3.4",
                "userAgent": "t",
            },
            "requestId": "r",
            "stage": "$default",
            "time": "01/Jan/2026:00:00:00 +0000",
            "timeEpoch": 1,
        },
        "isBase64Encoded": False,
    }
    ctx = MagicMock(function_name="f", aws_request_id="r", get_remaining_time_in_millis=lambda: 1000)
    res = api_handler.handler(event, ctx)
    assert res["statusCode"] == 200
    assert json.loads(res["body"])["items"][0]["project"] == "proj-a"


def test_openapi_contract_valid_and_in_sync():
    from pathlib import Path

    spec = create_app("all").openapi()
    validate(spec)
    committed = Path(__file__).resolve().parents[2] / "docs" / "openapi.yaml"
    assert yaml.safe_load(committed.read_text(encoding="utf-8")) == json.loads(json.dumps(spec)), (
        "run `make openapi`"
    )
    assert "/api/plans" in spec["paths"] and "/api/projects/{project}/diff" in spec["paths"]


def test_nested_states_are_listed_and_addressable_by_path(aws, ctx, svc, client, fixture_bytes):
    for key, fx in (
        ("proj-n/network/terraform.tfstate", "tf-1.5.7-serial8.tfstate"),
        ("proj-n/apps/web/prod.tfstate", "tf-0.15.5.tfstate"),
    ):
        vid = aws["s3"].put_object(Bucket=BUCKET, Key=key, Body=fixture_bytes(fx))["VersionId"]
        process_state_event(ctx, s3_event("Object Created", key, vid))
    items = client.get("/api/projects", params={"q": "proj-n"}).json()["items"]
    assert {(i["project"], i["path"]) for i in items} == {
        ("proj-n", "network/terraform.tfstate"),
        ("proj-n", "apps/web/prod.tfstate"),
    }
    r = client.get("/api/projects/proj-n", params={"path": "apps/web/prod.tfstate"})
    assert r.status_code == 200 and r.json()["path"] == "apps/web/prod.tfstate"
    assert client.get("/api/projects/proj-n").status_code == 404  # there is no terraform.tfstate at the root
    v = client.get("/api/projects/proj-n/versions/current", params={"path": "network/terraform.tfstate"})
    assert v.json()["info"]["s3_key"] == "proj-n/network/terraform.tfstate"
    hits = client.get("/api/search", params={"project": "proj-n", "path": "apps/web/prod.tfstate"}).json()
    assert hits["items"] and {h["path"] for h in hits["items"]} == {"apps/web/prod.tfstate"}
    d = client.get("/api/dashboard").json()
    assert d["projects"] == 3 and d["states"] == 4


def test_aws_resources_groups_terraform_into_aws_resources(client):
    r = client.get("/api/projects/proj-a/aws-resources").json()
    # the IAM access key arrives masked and its user is not in the state: it stays visible as an orphan
    assert r["map"]["state"] == "ok" and r["coverage"]["percent"] == 80.0  # 4 de 5
    kinds = sorted((x["cfn_type"], x["name"]) for x in r["resources"])
    assert ("AWS::S3::Bucket", "my-bucket-anon") in kinds
    assert sum(1 for k in kinds if k[0] == "AWS::EC2::Subnet") == 1
    assert ("AWS::SNS::Topic", "alerts") in kinds
    assert r["coverage"]["mapped"] == 4
    assert [(u["tf_type"], u["reason"]) for u in r["unmapped"]] == [("aws_iam_access_key", "orphan_child")]
    assert client.get("/api/projects/nope/aws-resources").status_code == 404


def test_aws_resources_fail_safe_when_map_is_broken(client, monkeypatch, tmp_path):
    from terraformation.aws_map.loader import load_map

    monkeypatch.setattr(
        "terraformation.api.app.default_map", lambda: load_map(tmp_path / "does-not-exist.json")
    )
    r = client.get("/api/projects/proj-a/aws-resources")
    assert r.status_code == 200  # a broken map never breaks the view
    body = r.json()
    assert body["map"]["state"] == "unavailable" and body["resources"] == []
    assert {u["reason"] for u in body["unmapped"]} == {"map_unavailable"}
    assert body["coverage"]["percent"] == 0.0 and body["coverage"]["unmapped"] == 5


def test_aws_resources_unknown_type_is_visible_not_guessed(client, monkeypatch, tmp_path):
    import json

    from terraformation.aws_map.loader import DEFAULT_PATH, load_map

    doc = json.loads(DEFAULT_PATH.read_text(encoding="utf-8"))
    del doc["entries"]["aws_subnet"]  # simulates an outdated map
    p = tmp_path / "old.json"
    p.write_text(json.dumps(doc), encoding="utf-8")
    monkeypatch.setattr("terraformation.api.app.default_map", lambda: load_map(p))
    body = client.get("/api/projects/proj-a/aws-resources").json()
    assert sorted((u["tf_type"], u["reason"]) for u in body["unmapped"]) == [
        ("aws_iam_access_key", "orphan_child"),
        ("aws_subnet", "no_rule"),
    ]
    assert body["coverage"]["mapped"] == 3


def test_aws_map_coverage_lists_gaps_across_projects(client, monkeypatch, tmp_path):
    import json

    from terraformation.aws_map.loader import DEFAULT_PATH, load_map

    ok = client.get("/api/aws-map/coverage").json()
    assert ok["states_checked"] == 2 and not ok["truncated"]
    gaps_ok = [t["tf_type"] for t in ok["types"] if not t["mapped"]]
    doc = json.loads(DEFAULT_PATH.read_text(encoding="utf-8"))
    del doc["entries"]["aws_vpc"]
    p = tmp_path / "old.json"
    p.write_text(json.dumps(doc), encoding="utf-8")
    monkeypatch.setattr("terraformation.api.app.default_map", lambda: load_map(p))
    body = client.get("/api/aws-map/coverage", params={"max_states": 1}).json()
    assert body["states_checked"] == 1 and body["truncated"] is True and body["states_total"] == 2
    assert "aws_vpc" not in gaps_ok
    gaps = {
        t["tf_type"]: t["reason"]
        for t in client.get("/api/aws-map/coverage").json()["types"]
        if not t["mapped"]
    }
    assert gaps["aws_vpc"] == "no_rule" and gaps["aws_iam_access_key"] == "orphan_child"
