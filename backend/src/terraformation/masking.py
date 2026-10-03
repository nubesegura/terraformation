"""Enmascarado de secretos: ``sensitive_attributes``, patrones de valores y nombres."""

from __future__ import annotations

import re
from typing import Any

MASK = "(sensitive)"

_VALUE_PATTERNS = [
    re.compile(p)
    for p in (
        r"\b(?:AKIA|ASIA|AGPA|AIDA|AROA)[0-9A-Z]{16}\b",  # AWS access key id
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----",  # PEM
        r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*",  # JWT
        r"\bgh[pousr]_[A-Za-z0-9]{30,}\b",  # GitHub
        r"\bxox[abprs]-[A-Za-z0-9-]{10,}",  # Slack
        r"\bsk_(?:live|test)_[A-Za-z0-9]{16,}",  # Stripe
        r"\bglpat-[A-Za-z0-9_-]{20,}",  # GitLab
        r"(?i)\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|amqps?|redis)://[^\s:/@]+:[^\s@]+@",
    )
]

_NAME_SENSITIVE = re.compile(
    r"(?:^|[._\-])(?:password|passwd|secret|token|private_key|api_key|apikey|access_key|"
    r"secret_key|client_secret|credentials?|authorization|connection_string|"
    r"secret_string|secret_binary|bcrypt_hash)(?:$|[._\-])",
    re.IGNORECASE,
)
_NAME_SAFE_SUFFIX = ("_arn", "_id", "_name", "_url", "_uri", "_endpoint", "_policy", "_length")


def value_looks_secret(value: str) -> bool:
    return any(p.search(value) for p in _VALUE_PATTERNS)


def name_looks_secret(key: str) -> bool:
    last = key.rsplit(".", 1)[-1].lower()
    if last.endswith(_NAME_SAFE_SUFFIX):
        return False
    return bool(_NAME_SENSITIVE.search(last))


def mask_leaf(key: str, value: str) -> str:
    """Enmascara un valor escalar ya convertido a texto."""
    if value == "" or value == MASK:
        return value
    if value_looks_secret(value) or name_looks_secret(key):
        return MASK
    return value


def normalize_path(path: list[dict[str, Any]]) -> tuple[str | int, ...]:
    """Convierte una ruta de ``sensitive_attributes`` en una tupla de pasos."""
    steps: list[str | int] = []
    for step in path:
        value = step.get("value")
        if step.get("type") == "index" and isinstance(value, dict):
            value = value.get("value")
        if isinstance(value, bool) or not isinstance(value, (str, int, float)):
            continue
        if isinstance(value, float):
            value = int(value) if value.is_integer() else str(value)
        steps.append(value)
    return tuple(steps)


def apply_sensitive_paths(attrs: Any, paths: list[list[dict[str, Any]]]) -> Any:
    """Copia ``attrs`` reemplazando por ``MASK`` los valores en rutas sensibles."""
    import copy

    out = copy.deepcopy(attrs)
    for raw in paths:
        steps = normalize_path(raw)
        if not steps:
            continue
        node: Any = out
        for step in steps[:-1]:
            node = _child(node, step)
            if node is None:
                break
        else:
            _set(node, steps[-1])
    return out


def _child(node: Any, step: str | int) -> Any:
    if isinstance(node, dict):
        return node.get(str(step))
    if isinstance(node, list) and isinstance(step, int) and 0 <= step < len(node):
        return node[step]
    return None


def _set(node: Any, step: str | int) -> None:
    if isinstance(node, dict) and str(step) in node and node[str(step)] is not None:
        node[str(step)] = MASK
    elif isinstance(node, list) and isinstance(step, int) and 0 <= step < len(node):
        node[step] = MASK
