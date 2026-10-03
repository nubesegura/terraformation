"""Carga del mapa Terraform -> recursos AWS. Nunca lanza: un mapa roto degrada la vista, no la rompe."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from functools import lru_cache
from pathlib import Path
from typing import Any

SUPPORTED_SCHEMA_VERSION = 1
DEFAULT_PATH = Path(__file__).with_name("resource_map.json")
CFN_TYPE_RE = re.compile(r"^[A-Za-z0-9]+::[A-Za-z0-9]+::[A-Za-z0-9]+$")
DEFAULT_STALE_DAYS = 180

# Estados del mapa: ok | degraded (hay entradas inválidas) | unavailable (no se pudo cargar)
STATE_OK = "ok"
STATE_DEGRADED = "degraded"
STATE_UNAVAILABLE = "unavailable"


@dataclass(frozen=True)
class ParentRule:
    type: str
    child_attr: str
    parent_attr: tuple[str, ...]


@dataclass(frozen=True)
class MapEntry:
    tf_type: str
    role: str  # primary | child
    status: str  # verified | provisional
    cfn_type: str | None = None
    identity: tuple[str, ...] = ()
    name: tuple[str, ...] = ()
    parent: ParentRule | None = None


@dataclass
class ResourceMap:
    state: str
    entries: dict[str, MapEntry] = field(default_factory=dict)
    invalid: dict[str, str] = field(default_factory=dict)  # tf_type -> motivo
    issues: list[str] = field(default_factory=list)
    reviewed_at: str | None = None
    stale: bool = False
    stale_after_days: int = DEFAULT_STALE_DAYS

    @property
    def usable(self) -> bool:
        return self.state != STATE_UNAVAILABLE


def _unavailable(reason: str) -> ResourceMap:
    return ResourceMap(state=STATE_UNAVAILABLE, issues=[reason])


def _strs(value: Any) -> tuple[str, ...] | None:
    if isinstance(value, list) and value and all(isinstance(v, str) and v for v in value):
        return tuple(value)
    return None


def _parse_entry(tf_type: str, raw: Any) -> MapEntry | str:
    """Devuelve la entrada o el motivo por el que es inválida."""
    if not isinstance(raw, dict):
        return "la entrada no es un objeto"
    role = raw.get("role")
    status = raw.get("status", "provisional")
    if status not in {"verified", "provisional"}:
        return f"status inválido: {status!r}"
    cfn = raw.get("cfn_type")
    if cfn is not None and not (isinstance(cfn, str) and CFN_TYPE_RE.match(cfn)):
        return f"cfn_type inválido: {cfn!r}"
    names: tuple[str, ...] = ()
    if "name" in raw:
        parsed_names = _strs(raw["name"])
        if parsed_names is None:
            return "name debe ser una lista de atributos"
        names = parsed_names
    if role == "primary":
        identity = _strs(raw.get("identity"))
        if cfn is None or identity is None:
            return "un recurso primario requiere cfn_type e identity"
        return MapEntry(tf_type, "primary", status, cfn, identity, names)
    if role == "child":
        p = raw.get("parent")
        if (
            not isinstance(p, dict)
            or not isinstance(p.get("type"), str)
            or not isinstance(p.get("child_attr"), str)
        ):
            return "un hijo requiere parent.type y parent.child_attr"
        parent_attr = _strs(p.get("parent_attr"))
        if parent_attr is None:
            return "parent.parent_attr debe ser una lista de atributos"
        if p["type"] == tf_type:
            return "un recurso no puede ser hijo de su mismo tipo"
        return MapEntry(
            tf_type, "child", status, cfn, (), names, ParentRule(p["type"], p["child_attr"], parent_attr)
        )
    return f"role inválido: {role!r}"


def _staleness(doc: dict[str, Any], today: date, rm: ResourceMap) -> None:
    days = doc.get("stale_after_days", DEFAULT_STALE_DAYS)
    rm.stale_after_days = days if isinstance(days, int) and days > 0 else DEFAULT_STALE_DAYS
    reviewed = doc.get("reviewed_at")
    rm.reviewed_at = reviewed if isinstance(reviewed, str) else None
    try:
        age = (today - date.fromisoformat(str(reviewed))).days
    except ValueError:
        rm.stale = True  # sin fecha de revisión válida se asume desactualizado
        rm.issues.append("reviewed_at ausente o inválido: el mapa se considera desactualizado")
        return
    rm.stale = age > rm.stale_after_days


def load_map(path: Path | None = None, today: date | None = None) -> ResourceMap:
    """Carga y valida el mapa. Jamás propaga excepciones."""
    today = today or datetime.now(UTC).date()
    try:
        doc = json.loads((path or DEFAULT_PATH).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return _unavailable(f"no se pudo leer el mapa: {type(exc).__name__}")
    if not isinstance(doc, dict) or doc.get("schema_version") != SUPPORTED_SCHEMA_VERSION:
        return _unavailable(f"schema_version no soportada (se esperaba {SUPPORTED_SCHEMA_VERSION})")
    raw_entries = doc.get("entries")
    if not isinstance(raw_entries, dict):
        return _unavailable("el mapa no contiene 'entries'")

    rm = ResourceMap(state=STATE_OK)
    for tf_type, raw in raw_entries.items():
        parsed = _parse_entry(tf_type, raw)
        if isinstance(parsed, str):
            rm.invalid[tf_type] = parsed
            rm.issues.append(f"{tf_type}: {parsed}")
        else:
            rm.entries[tf_type] = parsed
    if rm.invalid:
        rm.state = STATE_DEGRADED
    _staleness(doc, today, rm)
    return rm


@lru_cache(maxsize=1)
def default_map() -> ResourceMap:
    """Mapa empaquetado, cargado una vez por contenedor."""
    return load_map()
