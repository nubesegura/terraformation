"""Parser for the state format version 4 (Terraform 0.12 → 1.x and OpenTofu)."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from terraformation.masking import MASK, apply_sensitive_paths, mask_leaf
from terraformation.models import Instance, Output, ParsedState, StateSummary

MAX_VALUE_LEN = 4096
MAX_MODULES_SUMMARY = 50

_INSTANCE_KEY = re.compile(r'\["(?:[^"\\]|\\.)*"\]|\[\d+\]')
_PROVIDER = re.compile(r'provider\[\\?"(?P<src>[^"\\]+)\\?"\]|provider\.(?P<legacy>[\w-]+)')


class StateParseError(ValueError):
    """The content is not a valid v4 state."""


def strip_instance_keys(module: str) -> str:
    return _INSTANCE_KEY.sub("", module)


def short_provider(provider: str) -> str:
    """``provider["registry.terraform.io/hashicorp/aws"]`` → ``hashicorp/aws``."""
    m = _PROVIDER.search(provider or "")
    if not m:
        return provider or "unknown"
    if m["src"]:
        src = m["src"]
        return src.removeprefix("registry.terraform.io/").removeprefix("registry.opentofu.org/")
    return m["legacy"]


def _scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def flatten(value: Any, prefix: str = "", out: dict[str, str] | None = None) -> dict[str, str]:
    """Flattens attributes to ``dotted.key`` skipping nulls and applying masking."""
    out = {} if out is None else out
    if isinstance(value, dict):
        if not value and prefix:
            out[prefix] = "{}"
        for k in sorted(value):
            flatten(value[k], f"{prefix}.{k}" if prefix else str(k), out)
    elif isinstance(value, list):
        if not value and prefix:
            out[prefix] = "[]"
        for i, item in enumerate(value):
            flatten(item, f"{prefix}.{i}" if prefix else str(i), out)
    elif value is None:
        return out
    else:
        text = _scalar(value)
        text = mask_leaf(prefix, text)
        out[prefix] = text[:MAX_VALUE_LEN]
    return out


def _digest(obj: Any) -> str:
    return hashlib.sha256(json.dumps(obj, sort_keys=True, default=str).encode()).hexdigest()


def _index_suffix(index: Any) -> str:
    if index is None:
        return ""
    if isinstance(index, str):
        return f"[{json.dumps(index)}]"
    return f"[{_scalar(index)}]"


def _output_value(value: Any, sensitive: bool) -> str:
    if sensitive:
        return MASK
    flat = flatten(value, "value") if isinstance(value, (dict, list)) else None
    if flat is None:
        return mask_leaf("value", _scalar(value))[:MAX_VALUE_LEN] if value is not None else ""
    return json.dumps(
        {k.removeprefix("value.") if k != "value" else k: v for k, v in flat.items()},
        sort_keys=True,
    )[:MAX_VALUE_LEN]


def _type_str(t: Any) -> str:
    return t if isinstance(t, str) else json.dumps(t, separators=(",", ":"))


def parse_state(raw: bytes | str | dict[str, Any]) -> ParsedState:
    """Parses and masks a state. Raises :class:`StateParseError` if it is not v4."""
    try:
        data = json.loads(raw) if isinstance(raw, (bytes, str)) else raw
    except json.JSONDecodeError as exc:
        raise StateParseError(f"invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise StateParseError("the state must be a JSON object")
    version = data.get("version")
    if version != 4:
        raise StateParseError(f"unsupported state format: version={version!r} (only 4)")

    outputs = [
        Output(
            name=name,
            sensitive=bool(o.get("sensitive", False)),
            type=_type_str(o.get("type", "")),
            value=_output_value(o.get("value"), bool(o.get("sensitive", False))),
        )
        for name, o in sorted((data.get("outputs") or {}).items())
        if isinstance(o, dict)
    ]

    instances: list[Instance] = []
    for res in data.get("resources") or []:
        module = res.get("module") or "root"
        mode = res.get("mode", "managed")
        rtype, rname = res.get("type", ""), res.get("name", "")
        base = (
            ((module + ".") if module != "root" else "")
            + ("data." if mode == "data" else "")
            + f"{rtype}.{rname}"
        )
        provider = short_provider(res.get("provider", ""))
        for inst in res.get("instances") or []:
            index = inst.get("index_key")
            deposed = inst.get("deposed")
            address = base + _index_suffix(index) + (f" (deposed {deposed})" if deposed else "")
            raw_attrs = inst.get("attributes")
            if raw_attrs is None:
                raw_attrs = inst.get("attributes_flat") or {}
            masked = apply_sensitive_paths(raw_attrs, inst.get("sensitive_attributes") or [])
            instances.append(
                Instance(
                    address=address,
                    base_address=base,
                    module=module,
                    mode=mode,
                    type=rtype,
                    name=rname,
                    index=None if index is None else _scalar(index),
                    provider=provider,
                    status=inst.get("status"),
                    deposed=deposed,
                    attributes=flatten(masked),
                    dependencies=sorted(inst.get("dependencies") or []),
                    raw_digest=_digest(raw_attrs),
                )
            )
    return ParsedState(
        terraform_version=str(data.get("terraform_version", "")),
        serial=int(data.get("serial", 0)),
        lineage=str(data.get("lineage", "")),
        outputs=outputs,
        instances=instances,
    )


def summarize(state: ParsedState) -> StateSummary:
    by_type: dict[str, int] = {}
    by_provider: dict[str, int] = {}
    by_module: dict[str, int] = {}
    for i in state.instances:
        by_type[i.type] = by_type.get(i.type, 0) + 1
        by_provider[i.provider] = by_provider.get(i.provider, 0) + 1
        mod = i.module_base
        by_module[mod] = by_module.get(mod, 0) + 1
    top = dict(sorted(by_module.items(), key=lambda kv: -kv[1])[:MAX_MODULES_SUMMARY])
    return StateSummary(
        resource_count=len(state.instances),
        by_type=by_type,
        by_provider=by_provider,
        by_module=top,
    )


def content_hash(inst: Instance) -> str:
    """Hash of already masked content (safe to persist)."""
    return _digest([inst.attributes, inst.dependencies, inst.status, inst.provider])
