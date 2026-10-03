"""Verifica el mapa Terraform -> recursos AWS y propone entradas para los tipos que le faltan.

Uso (ver docs/AWS_MAP.md):

    python scripts/check_aws_map.py                          # estructura + tipos CloudFormation (si cfn-lint está)
    python scripts/check_aws_map.py --provider-schema s.json # además: tipos y atributos contra el proveedor AWS
    python scripts/check_aws_map.py --download-schema        # genera el esquema con `terraform providers schema`
    python scripts/check_aws_map.py --coverage cov.json      # informe de tipos sin mapear (GET /api/aws-map/coverage)
    python scripts/check_aws_map.py --coverage cov.json --propose

Las propuestas NUNCA se aplican solas: emparejar nombres sin revisión sería adivinar. Se imprimen para que una
persona las revise, ajuste la identidad y las copie a resource_map.json.
Código de salida 1 si el mapa tiene errores; los tipos sin mapear son un aviso (el mapa puede ir por detrás).
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
}  # `id` existe en todos los recursos aunque el esquema no lo liste siempre


def cfn_types() -> set[str] | None:
    """Tipos de CloudFormation conocidos (de cfn-lint). ``None`` si cfn-lint no está instalado."""
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
        sys.exit("terraform no está en el PATH: pasa --provider-schema <archivo>")
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
                sys.exit(f"falló `{' '.join(cmd[1:])}`: {r.stderr[:300]}")
        return json.loads(r.stdout)


def provider_resources(schema: dict) -> dict[str, set[str]]:
    res = schema["provider_schemas"][PROVIDER]["resource_schemas"]
    return {t: set(s["block"].get("attributes", {})) for t, s in res.items()}


def check_structure(rmap: ResourceMap) -> list[str]:
    errors: list[str] = []
    if rmap.state not in (STATE_OK, STATE_DEGRADED):
        return [f"el mapa no se puede cargar: {'; '.join(rmap.issues)}"]
    errors += [
        f"entrada inválida — {issue}"
        for issue in rmap.issues
        if not issue.startswith("reviewed_at")
    ]
    for tf, e in rmap.entries.items():
        if e.parent and e.parent.type not in rmap.entries:
            errors.append(f"{tf}: el padre {e.parent.type} no tiene entrada en el mapa")
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
        f"{tf}: cfn_type {e.cfn_type} no existe en CloudFormation"
        for tf, e in rmap.entries.items()
        if e.cfn_type and e.cfn_type not in known
    ]


def check_provider(rmap: ResourceMap, schema: dict[str, set[str]]) -> list[str]:
    errors: list[str] = []

    def ok_attr(tf: str, attr: str) -> bool:
        return attr in ALWAYS_VALID_ATTRS or attr in schema[tf]

    for tf, e in rmap.entries.items():
        if tf not in schema:
            errors.append(f"{tf}: el tipo no existe en el proveedor AWS")
            continue
        for attr in (*e.identity, *e.name):
            if not ok_attr(tf, attr):
                errors.append(f"{tf}: el atributo '{attr}' no existe en el esquema")
        if e.parent:
            if not ok_attr(tf, e.parent.child_attr):
                errors.append(
                    f"{tf}: child_attr '{e.parent.child_attr}' no existe en el esquema"
                )
            if e.parent.type in schema:
                for attr in e.parent.parent_attr:
                    if not ok_attr(e.parent.type, attr):
                        errors.append(
                            f"{tf}: parent_attr '{attr}' no existe en {e.parent.type}"
                        )
    return errors


def normalize_cfn(cfn: str) -> str:
    return cfn.removeprefix("AWS::").replace("::", "_").lower()


def propose(types: list[str], known: set[str] | None) -> None:
    index = {normalize_cfn(c): c for c in known or ()}
    print("\n== Propuestas (REVISIÓN HUMANA OBLIGATORIA; no se aplican) ==")
    for tf in types:
        cfn = index.get(tf.removeprefix("aws_"))
        if cfn is None:
            print(
                f"- {tf}: sin candidato exacto en CloudFormation; mapear a mano si procede (¿es hijo de otro recurso?)"
            )
            continue
        entry = {
            "role": "primary",
            "cfn_type": cfn,
            "identity": ["arn", "id"],
            "status": "provisional",
        }
        print(
            f'- {tf}: candidato {cfn} (coincidencia exacta de nombre, NO verificada)\n  "{tf}": {json.dumps(entry)}'
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
        f"mapa: estado={rmap.state} entradas={len(rmap.entries)} revisado={rmap.reviewed_at} desactualizado={rmap.stale}"
    )
    known = cfn_types()
    if known is None:
        print(
            "aviso: cfn-lint no está instalado; no se comprueban los tipos de CloudFormation"
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
            "aviso: sin esquema del proveedor; no se comprueban tipos ni atributos de Terraform"
        )
    if rmap.stale:
        print(f"aviso: el mapa lleva más de {rmap.stale_after_days} días sin revisarse")
        if args.fail_on_stale:
            errors.append("mapa desactualizado")

    if args.coverage:
        gaps = read_unmapped(args.coverage)
        print(f"\ntipos aws_* sin mapear en el bucket: {len(gaps)}")
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
