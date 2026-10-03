"""Generates lifecycle rules to expire NON-current versions of the .tflock files.

S3 does not filter by suffix; we use the exact key of each lock as ``Prefix``
(``<state-key>.tflock``), which is not a prefix of any ``.tfstate``.

Usage (read-only on AWS; you apply the result yourself):

    aws s3api list-objects-v2 --bucket MI_BUCKET --query 'Contents[].Key' --output text \
      | tr '\\t' '\\n' | python scripts/lifecycle_tflock.py --days 30 > rules.json

IMPORTANT: PutBucketLifecycleConfiguration replaces the WHOLE configuration; merge these
rules with the ones you already have (``aws s3api get-bucket-lifecycle-configuration``).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from typing import Any

MAX_RULES = 1000


def build_rules(keys: list[str], days: int) -> list[dict[str, Any]]:
    prefixes = sorted(
        {k + ".tflock" for k in keys if k.endswith(".tfstate") and "/" in k}
    )
    rules = []
    for prefix in prefixes:
        digest = hashlib.sha1(prefix.encode()).hexdigest()[:10]
        rules.append(
            {
                "ID": f"tflock-noncurrent-{digest}",
                "Status": "Enabled",
                "Filter": {"Prefix": prefix},
                "NoncurrentVersionExpiration": {"NoncurrentDays": days},
            }
        )
    if len(rules) > MAX_RULES:
        raise SystemExit(
            f"{len(rules)} rules exceed the limit of {MAX_RULES} per bucket"
        )
    return rules


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--days",
        type=int,
        default=30,
        help="retention days for non-current versions",
    )
    args = ap.parse_args()
    keys = [line.strip() for line in sys.stdin if line.strip()]
    json.dump({"Rules": build_rules(keys, args.days)}, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
