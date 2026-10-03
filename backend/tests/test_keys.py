from terraformation.keys import StateRef, parse_key, parse_lock_key, split_sid


def test_default_workspace():
    assert parse_key("proj-a/terraform.tfstate") == StateRef("proj-a", "default", "terraform.tfstate")


def test_named_workspace():
    assert parse_key("env:/dev/proj-a/terraform.tfstate") == StateRef("proj-a", "dev")


def test_env_prefix_is_not_a_project():
    assert parse_key("env:/terraform.tfstate") is None
    assert parse_key("env:/dev/x.tfstate") is None


def test_lock_files_never_match_state():
    assert parse_key("proj-a/terraform.tfstate.tflock") is None
    assert parse_key("env:/dev/proj-a/terraform.tfstate.tflock") is None


def test_lock_key():
    assert parse_lock_key("proj-a/terraform.tfstate.tflock") == StateRef("proj-a")
    assert parse_lock_key("env:/dev/p/net/main.tfstate.tflock") == StateRef("p", "dev", "net/main.tfstate")
    assert parse_lock_key("p/terraform.tfstate") is None


def test_bucket_root_state_has_no_project():
    assert parse_key("terraform.tfstate") is None
    assert parse_key("/terraform.tfstate") is None


def test_nested_and_any_filename():
    assert parse_key("a/b/terraform.tfstate") == StateRef("a", "default", "b/terraform.tfstate")
    assert parse_key("a/prod.tfstate") == StateRef("a", "default", "prod.tfstate")
    assert parse_key("a/x/y/z/db.tfstate") == StateRef("a", "default", "x/y/z/db.tfstate")
    assert parse_key("env:/qa/a/x/db.tfstate") == StateRef("a", "qa", "x/db.tfstate")
    assert parse_key("a/readme.txt") is None
    assert parse_key("a//x.tfstate") is None


def test_roundtrip():
    for ref in (StateRef("p", "qa", "net/main.tfstate"), StateRef("p", "default", "x.tfstate")):
        assert parse_key(ref.state_key) == ref
        assert parse_lock_key(ref.lock_key) == ref
        assert split_sid(ref.sid) == ref
    assert StateRef("p", "qa", "main.tfstate").lock_key == "env:/qa/p/main.tfstate.tflock"
