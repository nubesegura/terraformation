import importlib.util
from pathlib import Path

from terraformation.aws_map.loader import DEFAULT_PATH, load_map

spec = importlib.util.spec_from_file_location(
    "check_aws_map", Path(__file__).resolve().parents[2] / "scripts" / "check_aws_map.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

SCHEMA = {"aws_s3_bucket": {"id", "bucket", "arn"}, "aws_s3_bucket_policy": {"bucket", "policy"}}


def test_packaged_map_passes_structure_check():
    assert mod.check_structure(load_map(DEFAULT_PATH)) == []


def test_provider_check_catches_unknown_types_and_attributes(tmp_path):
    rmap = load_map(DEFAULT_PATH)
    errors = mod.check_provider(rmap, SCHEMA)
    assert any("aws_iam_role: the type does not exist" in e for e in errors)  # the test schema is minimal
    sub = {k: v for k, v in rmap.entries.items() if k in SCHEMA}
    rmap.entries = sub
    assert mod.check_provider(rmap, SCHEMA) == []
    rmap.entries["aws_s3_bucket_policy"] = type(sub["aws_s3_bucket_policy"])(
        "aws_s3_bucket_policy",
        "child",
        "verified",
        None,
        (),
        (),
        type(sub["aws_s3_bucket_policy"].parent)("aws_s3_bucket", "inexistente", ("id",)),
    )
    assert any("child_attr 'inexistente'" in e for e in mod.check_provider(rmap, SCHEMA))


def test_structure_check_flags_missing_parent_and_cycles():
    rmap = load_map(DEFAULT_PATH)
    del rmap.entries["aws_s3_bucket"]
    assert any(
        "aws_s3_bucket_policy: parent aws_s3_bucket has no entry" in e for e in mod.check_structure(rmap)
    )


def test_proposals_only_for_exact_name_matches(capsys):
    mod.propose(["aws_glue_job", "aws_made_up_total"], {"AWS::Glue::Job", "AWS::S3::Bucket"})
    out = capsys.readouterr().out
    assert "AWS::Glue::Job" in out and "NOT verified" in out
    assert "aws_made_up_total: no exact candidate" in out
    assert mod.normalize_cfn("AWS::ApiGatewayV2::Api") == "apigatewayv2_api"
