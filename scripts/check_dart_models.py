"""Verifica que los modelos Dart (`// openapi: Schema`) usen solo campos del contrato OpenAPI
y cubran todos los campos requeridos. Uso: `python scripts/check_dart_models.py`."""

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
            problems.append(f"{name}: no existe en OpenAPI")
            continue
        props = set(schemas[name].get("properties", {}))
        required = set(schemas[name].get("required", []))
        # `allOf` (herencia en ActiveLock) no se usa; las propiedades se aplanan en FastAPI.
        extra = keys - props
        if extra:
            problems.append(
                f"{name}: campos Dart inexistentes en el contrato: {sorted(extra)}"
            )
        missing = required - keys
        if missing:
            problems.append(
                f"{name}: campos requeridos sin leer en Dart: {sorted(missing)}"
            )
    return problems


if __name__ == "__main__":
    issues = check()
    print(
        "\n".join(issues)
        if issues
        else f"modelos Dart alineados con OpenAPI ({len(dart_fields())} esquemas)"
    )
    sys.exit(1 if issues else 0)
