"""Exporta el contrato OpenAPI (YAML) desde la app FastAPI: `python scripts/export_openapi.py`."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml
from terraformation.api.app import create_app

OUT = Path(__file__).resolve().parent.parent / "docs" / "openapi.yaml"


def render() -> str:
    spec = create_app("all").openapi()
    return yaml.safe_dump(spec, sort_keys=True, allow_unicode=True, width=100)


if __name__ == "__main__":
    text = render()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            sys.exit("docs/openapi.yaml está desactualizado: ejecuta `make openapi`")
        sys.exit(0)
    # bytes: evita la conversión de saltos de línea en Windows
    OUT.write_bytes(text.encode("utf-8"))
    print(f"escrito {OUT}")
