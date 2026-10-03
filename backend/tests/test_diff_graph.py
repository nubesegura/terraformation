from terraformation.diff import count_changes, diff_states
from terraformation.graph import build_graph
from terraformation.models import StateInfo
from terraformation.parser import parse_state


def _states(fixture_bytes):
    return (
        parse_state(fixture_bytes("tf-1.5.7-serial8.tfstate")),
        parse_state(fixture_bytes("tf-1.5.7-serial9.tfstate")),
    )


def test_diff(fixture_bytes):
    a, b = _states(fixture_bytes)
    d = diff_states(a, b, StateInfo(version_id="v8"), StateInfo(version_id="v9"))
    assert [r.address for r in d.added] == ["aws_sns_topic.alerts"]
    assert [r.address for r in d.removed] == ['module.net.aws_subnet.s["b"]']
    mods = {m.address: m for m in d.modified}
    assert set(mods) == {"aws_s3_bucket.logs", "aws_iam_access_key.ci"}
    bucket = mods["aws_s3_bucket.logs"]
    kinds = {(c.key, c.kind) for c in bucket.changes}
    assert ("tags.team", "changed") in kinds and ("tags.cost", "added") in kinds
    assert "-" in bucket.unified_diff and "+" in bucket.unified_diff
    assert mods["aws_iam_access_key.ci"].sensitive_changed
    assert not mods["aws_iam_access_key.ci"].changes
    assert d.summary.added == 1 and d.summary.removed == 1 and d.summary.modified == 2
    assert d.summary.unchanged == 2
    assert [o.name for o in d.outputs] == ["bucket"]
    assert d.from_.version_id == "v8" and d.to.serial == 9
    assert "zzzz" not in d.model_dump_json()


def test_diff_identical_has_no_changes(fixture_bytes):
    a, _ = _states(fixture_bytes)
    d = diff_states(a, a)
    assert d.summary.modified == 0 and not d.added and not d.removed and not d.outputs


def test_count_changes(fixture_bytes):
    a, b = _states(fixture_bytes)
    assert count_changes(None, a) == (len(a.instances), 0, 0)
    assert count_changes(a, b) == (1, 1, 2)


def test_graph(fixture_bytes):
    a, _ = _states(fixture_bytes)
    g = build_graph(a)
    ids = {n.id for n in g.nodes}
    assert "module.net.aws_subnet.s" in ids and "module.net" in ids
    sub = next(n for n in g.nodes if n.id == "module.net.aws_subnet.s")
    assert sub.instances == 2
    edges = {(e.source, e.target) for e in g.edges}
    assert ("aws_iam_access_key.ci", "aws_s3_bucket.logs") in edges
    assert ("aws_s3_bucket.logs", "module.net") in edges
    assert ("module.net.aws_subnet.s", "module.net.aws_vpc.v") in edges
    me = {(e.source, e.target): e.count for e in g.module_edges}
    assert me[("root", "module.net")] == 1
