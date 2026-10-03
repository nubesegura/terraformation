import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "lifecycle_tflock", Path(__file__).resolve().parents[2] / "scripts" / "lifecycle_tflock.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_rules_target_only_lock_keys():
    keys = [
        "a/terraform.tfstate",
        "env:/dev/a/terraform.tfstate",
        "a/net/prod.tfstate",
        "a/other.txt",
        "terraform.tfstate",
    ]
    rules = mod.build_rules(keys, 14)
    prefixes = {r["Filter"]["Prefix"] for r in rules}
    assert prefixes == {
        "a/terraform.tfstate.tflock",
        "env:/dev/a/terraform.tfstate.tflock",
        "a/net/prod.tfstate.tflock",
    }
    assert all(set(r) == {"ID", "Status", "Filter", "NoncurrentVersionExpiration"} for r in rules)
    assert all(r["NoncurrentVersionExpiration"] == {"NoncurrentDays": 14} for r in rules)
    # no rule can reach a .tfstate: the prefix ends in .tflock
    assert all(p.endswith(".tflock") for p in prefixes)
    assert not any(k.startswith(p) for k in keys for p in prefixes)
