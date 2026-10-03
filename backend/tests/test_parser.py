import pytest

from terraformation.masking import MASK
from terraformation.parser import StateParseError, parse_state, short_provider, summarize


def test_tf012(fixture_bytes):
    s = parse_state(fixture_bytes("tf-0.12.31.tfstate"))
    assert s.terraform_version == "0.12.31" and s.serial == 3
    addrs = {i.address for i in s.instances}
    assert addrs == {
        "aws_vpc.main",
        "aws_instance.web[0]",
        "aws_instance.web[1]",
        "data.aws_ami.ubuntu",
    }
    vpc = next(i for i in s.instances if i.address == "aws_vpc.main")
    assert vpc.attributes["tags.Name"] == "main" and vpc.provider == "aws"
    assert next(i for i in s.instances if i.mode == "data").type == "aws_ami"


def test_sensitive_attributes_and_outputs_masked(fixture_bytes):
    s = parse_state(fixture_bytes("tf-0.15.5.tfstate"))
    db = next(i for i in s.instances if i.type == "aws_db_instance")
    assert db.module == "module.db" and db.address == "module.db.aws_db_instance.this"
    assert db.attributes["password"] == MASK and db.attributes["engine"] == "postgres"
    assert db.dependencies == ["module.db.aws_security_group.db"]
    rp = next(i for i in s.instances if i.type == "random_password")
    assert rp.attributes["result"] == MASK and rp.provider == "hashicorp/random"
    outs = {o.name: o for o in s.outputs}
    assert outs["db_password"].value == MASK and outs["db_password"].sensitive
    assert outs["endpoint"].value == "db.example.internal"
    assert "hunter2" not in s.model_dump_json()


def test_pattern_masking_and_index_keys(fixture_bytes):
    s = parse_state(fixture_bytes("tf-1.5.7-serial8.tfstate"))
    key = next(i for i in s.instances if i.type == "aws_iam_access_key")
    assert key.attributes["secret"] == MASK
    assert key.attributes["id"] == MASK  # patrón AKIA...
    subs = sorted(i.address for i in s.instances if i.type == "aws_subnet")
    assert subs == ['module.net.aws_subnet.s["a"]', 'module.net.aws_subnet.s["b"]']
    assert "wJalr" not in s.model_dump_json()
    cfg = next(o for o in s.outputs if o.name == "cfg")
    assert '"b.1": "y"' in cfg.value


def test_name_heuristic_and_nulls(fixture_bytes):
    s = parse_state(fixture_bytes("opentofu-1.8-tf-1.9.8.tfstate"))
    fn = next(i for i in s.instances if i.type == "aws_lambda_function")
    assert fn.attributes["environment.0.variables.API_TOKEN"] == MASK
    assert fn.attributes["environment.0.variables.LOG"] == "info"
    assert "description" not in fn.attributes
    assert fn.attributes["publish"] == "false" and fn.attributes["memory_size"] == "128"
    assert next(i for i in s.instances if i.type == "aws_iam_role").status == "tainted"
    assert fn.provider == "hashicorp/aws"


def test_unsupported_and_invalid(fixture_bytes):
    with pytest.raises(StateParseError, match="version=3"):
        parse_state(fixture_bytes("unsupported-v3.tfstate"))
    with pytest.raises(StateParseError):
        parse_state(b"not json")
    with pytest.raises(StateParseError):
        parse_state(b"[]")


def test_summary(fixture_bytes):
    s = summarize(parse_state(fixture_bytes("tf-1.5.7-serial8.tfstate")))
    assert s.resource_count == 5
    assert s.by_type["aws_subnet"] == 2
    assert s.by_module["module.net"] == 3 and s.by_module["root"] == 2


def test_short_provider():
    assert short_provider('provider["registry.terraform.io/hashicorp/aws"]') == "hashicorp/aws"
    assert short_provider("provider.aws") == "aws"
    assert short_provider("") == "unknown"
