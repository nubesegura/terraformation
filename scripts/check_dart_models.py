"""Checks that the Dart models (`// openapi: Schema`) use only fields from the OpenAPI contract
and cover all required fields. Usage: `python scripts/check_dart_models.py`."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "frontend" / "lib" / "core" / "api" / "models.dart"
SPEC = ROOT / "docs" / "openapi.yaml"


def dart_fields() -> dict[str, set[str]]:
    text = MODELS.read_text(encoding="utf-8")
    blocks = re.split(r"^// openapi: (\w+)\n", text, flags=re.MULTILINE)
    out: dict[str, set[str]] = {}
    for name, body in zip(blocks[1::2], blocks[2::2], strict=True):
        keys = set(re.findall(r"""_(?:s|sn|i|in|b|l|mi|ms)\(\s*j,\s*'(\w+)'""", body))
        keys |= set(re.findall(r"""j\['(\w+)'\]""", body))
        out[name] = keys
    return out


def check() -> list[str]:
    spec = yaml.safe_load(SPEC.read_text(encoding="utf-8"))
    schemas = spec["components"]["schemas"]
    problems: list[str] = []
    for name, keys in dart_fields().items():
        if name not in schemas:
            problems.append(f"{name}: does not exist in OpenAPI")
            continue
        props = set(schemas[name].get("properties", {}))
        required = set(schemas[name].get("required", []))
        # `allOf` (inheritance in ActiveLock) is not used; properties are flattened in FastAPI.
        extra = keys - props
        if extra:
            problems.append(
                f"{name}: Dart fields missing from the contract: {sorted(extra)}"
            )
        missing = required - keys
        if missing:
            problems.append(
                f"{name}: required fields not read in Dart: {sorted(missing)}"
            )
    return problems


if __name__ == "__main__":
    issues = check()
    print(
        "\n".join(issues)
        if issues
        else f"Dart models aligned with OpenAPI ({len(dart_fields())} schemas)"
    )
    sys.exit(1 if issues else 0)
