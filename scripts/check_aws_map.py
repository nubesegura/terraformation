"""Checks the Terraform -> AWS resources map and proposes entries for the types it lacks.

Usage (see docs/AWS_MAP.md):

    python scripts/check_aws_map.py                          # structure + CloudFormation types (if cfn-lint is installed)
    python scripts/check_aws_map.py --provider-schema s.json # also: types and attributes against the AWS provider
    python scripts/check_aws_map.py --download-schema        # generates the schema with `terraform providers schema`
    python scripts/check_aws_map.py --coverage cov.json      # report of unmapped types (GET /api/aws-map/coverage)
    python scripts/check_aws_map.py --coverage cov.json --propose

Proposals are NEVER applied automatically: matching names without review would be guessing. They are printed so a
person can review them, adjust the identity and copy them to resource_map.json.
Exit code 1 if the map has errors; unmapped types are a warning (the map may lag behind).
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend" / "src"))

from terraformation.aws_map.loader import (
    DEFAULT_PATH,
    STATE_DEGRADED,
    STATE_OK,
    ResourceMap,
    load_map,
)

PROVIDER = "registry.terraform.io/hashicorp/aws"
ALWAYS_VALID_ATTRS = {
    "id"
}  # `id` exists on every resource even if the schema does not always list it


def cfn_types() -> set[str] | None:
    """Known CloudFormation types (from cfn-lint). ``None`` if cfn-lint is not installed."""
    try:
        import cfnlint
    except ImportError:
        return None
    path = (
        Path(cfnlint.__file__).parent
        / "data"
        / "schemas"
        / "providers"
        / "us-east-1.json"
    )
    try:
        return set(json.loads(path.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        return None


def download_schema() -> dict:
    terraform = shutil.which("terraform")
    if not terraform:
        sys.exit("terraform is not on the PATH: pass --provider-schema <file>")
    with tempfile.TemporaryDirectory() as tmp:
        Path(tmp, "main.tf").write_text(
            'terraform { required_providers { aws = { source = "hashicorp/aws" } } }\n',
            encoding="utf-8",
        )
        for cmd in (
            [terraform, "init", "-input=false", "-no-color"],
            [terraform, "providers", "schema", "-json"],
        ):
            r = subprocess.run(
                cmd, cwd=tmp, capture_output=True, text=True, check=False
            )
            if r.returncode:
                sys.exit(f"failed `{' '.join(cmd[1:])}`: {r.stderr[:300]}")
        return json.loads(r.stdout)


def provider_resources(schema: dict) -> dict[str, set[str]]:
    res = schema["provider_schemas"][PROVIDER]["resource_schemas"]
    return {t: set(s["block"].get("attributes", {})) for t, s in res.items()}


def check_structure(rmap: ResourceMap) -> list[str]:
    errors: list[str] = []
    if rmap.state not in (STATE_OK, STATE_DEGRADED):
        return [f"the map cannot be loaded: {'; '.join(rmap.issues)}"]
    errors += [
        f"invalid entry — {issue}"
        for issue in rmap.issues
        if not issue.startswith("reviewed_at")
    ]
    for tf, e in rmap.entries.items():
        if e.parent and e.parent.type not in rmap.entries:
            errors.append(f"{tf}: parent {e.parent.type} has no entry in the map")
        seen, cur = {tf}, e
        while cur.parent and cur.parent.type in rmap.entries:
            cur = rmap.entries[cur.parent.type]
            if cur.tf_type in seen:
                errors.append(f"{tf}: ciclo de padres")
                break
            seen.add(cur.tf_type)
    return errors


def check_cfn(rmap: ResourceMap, known: set[str]) -> list[str]:
    return [
        f"{tf}: cfn_type {e.cfn_type} does not exist in CloudFormation"
        for tf, e in rmap.entries.items()
        if e.cfn_type and e.cfn_type not in known
    ]


def check_provider(rmap: ResourceMap, schema: dict[str, set[str]]) -> list[str]:
    errors: list[str] = []

    def ok_attr(tf: str, attr: str) -> bool:
        return attr in ALWAYS_VALID_ATTRS or attr in schema[tf]

    for tf, e in rmap.entries.items():
        if tf not in schema:
            errors.append(f"{tf}: the type does not exist in the AWS provider")
            continue
        for attr in (*e.identity, *e.name):
            if not ok_attr(tf, attr):
                errors.append(f"{tf}: attribute '{attr}' does not exist in the schema")
        if e.parent:
            if not ok_attr(tf, e.parent.child_attr):
                errors.append(
                    f"{tf}: child_attr '{e.parent.child_attr}' does not exist in the schema"
                )
            if e.parent.type in schema:
                for attr in e.parent.parent_attr:
                    if not ok_attr(e.parent.type, attr):
                        errors.append(
                            f"{tf}: parent_attr '{attr}' does not exist in {e.parent.type}"
                        )
    return errors


def normalize_cfn(cfn: str) -> str:
    return cfn.removeprefix("AWS::").replace("::", "_").lower()


def propose(types: list[str], known: set[str] | None) -> None:
    index = {normalize_cfn(c): c for c in known or ()}
    print("\n== Proposals (HUMAN REVIEW REQUIRED; not applied) ==")
    for tf in types:
        cfn = index.get(tf.removeprefix("aws_"))
        if cfn is None:
            print(
                f"- {tf}: no exact candidate in CloudFormation; map by hand if appropriate (is it a child of another resource?)"
            )
            continue
        entry = {
            "role": "primary",
            "cfn_type": cfn,
            "identity": ["arn", "id"],
            "status": "provisional",
        }
        print(
            f'- {tf}: candidate {cfn} (exact name match, NOT verified)\n  "{tf}": {json.dumps(entry)}'
        )


def read_unmapped(path: Path) -> list[str]:
    doc = json.loads(path.read_text(encoding="utf-8"))
    return [
        t["tf_type"]
        for t in doc.get("types", [])
        if not t.get("mapped", True) and t["tf_type"].startswith("aws_")
    ]


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # consolas de Windows en cp1252
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--map", type=Path, default=DEFAULT_PATH)
    ap.add_argument("--provider-schema", type=Path)
    ap.add_argument("--download-schema", action="store_true")
    ap.add_argument("--coverage", type=Path, help="JSON de GET /api/aws-map/coverage")
    ap.add_argument("--propose", action="store_true")
    ap.add_argument("--fail-on-stale", action="store_true")
    args = ap.parse_args()

    rmap = load_map(args.map)
    errors = check_structure(rmap)
    print(
        f"map: state={rmap.state} entries={len(rmap.entries)} reviewed={rmap.reviewed_at} stale={rmap.stale}"
    )
    known = cfn_types()
    if known is None:
        print(
            "warning: cfn-lint is not installed; CloudFormation types are not checked"
        )
    else:
        errors += check_cfn(rmap, known)
    schema = None
    if args.provider_schema:
        schema = json.loads(args.provider_schema.read_text(encoding="utf-8"))
    elif args.download_schema:
        schema = download_schema()
    if schema is not None:
        errors += check_provider(rmap, provider_resources(schema))
    else:
        print(
            "warning: no provider schema; Terraform types and attributes are not checked"
        )
    if rmap.stale:
        print(
            f"warning: the map has gone more than {rmap.stale_after_days} days without review"
        )
        if args.fail_on_stale:
            errors.append("map is stale")

    if args.coverage:
        gaps = read_unmapped(args.coverage)
        print(f"\nunmapped aws_* types in the bucket: {len(gaps)}")
        for t in gaps:
            print(f"- {t}")
        if args.propose:
            propose(gaps, known)

    for e in errors:
        print(f"ERROR: {e}")
    print("OK" if not errors else f"{len(errors)} error(es)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
