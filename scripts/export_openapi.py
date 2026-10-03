"""Exports the OpenAPI contract (YAML) from the FastAPI app: `python scripts/export_openapi.py`."""

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
            sys.exit("docs/openapi.yaml is out of date: run `make openapi`")
        sys.exit(0)
    # bytes: avoids newline conversion on Windows
    OUT.write_bytes(text.encode("utf-8"))
    print(f"written {OUT}")
