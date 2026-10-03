"""Groups the instances of a state into AWS resources. Fails safe: anything doubtful goes to "unmapped".

Rules:
* Never matched by name or similarity: only by the map's explicit rules.
* Every managed resource ends up in exactly one group: AWS resource, unmapped, helper or data.
* If the map is unavailable, no managed resource is considered mapped.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

from terraformation.aws_map.loader import MapEntry, ResourceMap
from terraformation.masking import MASK

# Providers that do not create AWS infrastructure (utilities). Listed separately, not hidden.
HELPER_PROVIDERS = frozenset(
    {"random", "time", "null", "local", "tls", "archive", "external", "template", "http", "cloudinit"}
)

# Reasons for "unmapped"
NO_RULE = "no_rule"
NON_AWS_PROVIDER = "non_aws_provider"
MISSING_IDENTITY = "missing_identity"
MISSING_PARENT_REF = "missing_parent_ref"
ORPHAN_CHILD = "orphan_child"
AMBIGUOUS_PARENT = "ambiguous_parent"
INVALID_ENTRY = "invalid_map_entry"
MAP_UNAVAILABLE = "map_unavailable"

MAX_CHAIN_DEPTH = 5


@dataclass
class Component:
    address: str
    tf_type: str
    cfn_type: str | None = None


@dataclass
class AwsGroup:
    cfn_type: str
    identity: str
    name: str
    status: str  # verified | provisional
    primaries: list[Component] = field(default_factory=list)
    components: list[Component] = field(default_factory=list)


@dataclass
class Unmapped:
    address: str
    tf_type: str
    reason: str
    detail: str = ""
    module: str = "root"


@dataclass
class Resolution:
    groups: list[AwsGroup] = field(default_factory=list)
    unmapped: list[Unmapped] = field(default_factory=list)
    helpers: list[Component] = field(default_factory=list)
    data: list[Component] = field(default_factory=list)

    def coverage(self) -> dict[str, Any]:
        mapped = sum(len(g.primaries) + len(g.components) for g in self.groups)
        total = mapped + len(self.unmapped)
        by_reason: dict[str, int] = defaultdict(int)
        for u in self.unmapped:
            by_reason[u.reason] += 1
        return {
            "managed_total": total,
            "mapped": mapped,
            "unmapped": len(self.unmapped),
            "percent": round(100 * mapped / total, 1) if total else 100.0,
            "unmapped_by_reason": dict(sorted(by_reason.items())),
            "aws_resources": len(self.groups),
        }


def provider_short(provider: str) -> str:
    """``registry.terraform.io/hashicorp/aws`` / ``provider["..."]`` / ``provider.aws`` -> ``aws``."""
    text = (
        provider.strip().strip('"[]').replace("provider", "", 1)
        if provider.startswith("provider")
        else provider
    )
    text = text.strip('."[] ')
    return text.rsplit("/", 1)[-1].split(".")[0].split('"')[0] if text else ""


def _usable(value: Any) -> str | None:
    if isinstance(value, str) and value and value != MASK:
        return value
    return None


def _first(attrs: dict[str, str], keys: tuple[str, ...]) -> str | None:
    for k in keys:
        v = _usable(attrs.get(k))
        if v is not None:
            return v
    return None


def _display_name(entry: MapEntry, attrs: dict[str, str], identity: str) -> str:
    name = _first(attrs, entry.name)
    if name:
        return name
    return identity.rsplit("/", 1)[-1].rsplit(":", 1)[-1] or identity


@dataclass
class _Node:
    item: dict[str, Any]
    entry: MapEntry


def _unmapped(item: dict[str, Any], reason: str, detail: str = "") -> Unmapped:
    return Unmapped(item.get("address", ""), item.get("type", ""), reason, detail, item.get("module", "root"))


# Terraform type -> [(attributes, root group)] of the already resolved resources
_Registry = dict[str, list[tuple[dict[str, str], AwsGroup]]]


def _find_parent_group(node: _Node, registry: _Registry) -> tuple[AwsGroup | None, str]:
    """Root group of the parent. ``(None, "")`` = not resolved yet; ``(None, reason)`` = final."""
    rule = node.entry.parent
    assert rule is not None
    value = _usable((node.item.get("attrs") or {}).get(rule.child_attr))
    if value is None:
        return None, MISSING_PARENT_REF
    matches: dict[int, AwsGroup] = {}
    for attrs, group in registry.get(rule.type, []):
        if any(_usable(attrs.get(a)) == value for a in rule.parent_attr):
            matches[id(group)] = group
    if len(matches) > 1:
        return None, AMBIGUOUS_PARENT
    if matches:
        return next(iter(matches.values())), ""
    return None, ""


def _resolve_children(out: Resolution, children: list[_Node], registry: _Registry) -> None:
    pending = children
    for _ in range(MAX_CHAIN_DEPTH):
        still: list[_Node] = []
        for node in pending:
            group, reason = _find_parent_group(node, registry)
            if reason:
                detail = (
                    "the link attribute has no usable value"
                    if reason == MISSING_PARENT_REF
                    else "the parent matches more than one resource"
                )
                out.unmapped.append(_unmapped(node.item, reason, detail))
            elif group is None:
                still.append(node)
            else:
                tf_type = node.item.get("type", "")
                group.components.append(Component(node.item.get("address", ""), tf_type, node.entry.cfn_type))
                if node.entry.status == "provisional":
                    group.status = "provisional"
                registry.setdefault(tf_type, []).append((node.item.get("attrs") or {}, group))
        if len(still) == len(pending):
            pending = still
            break
        pending = still
    for node in pending:
        rule = node.entry.parent
        parent_type = rule.type if rule else "?"
        out.unmapped.append(
            _unmapped(node.item, ORPHAN_CHILD, f"parent ({parent_type}) not found in this state")
        )


def resolve(items: list[dict[str, Any]], rmap: ResourceMap) -> Resolution:
    """``items``: RES# items (address, type, name, module, provider, mode, attrs)."""
    out = Resolution()
    groups: dict[tuple[str, str], AwsGroup] = {}
    registry: _Registry = {}
    children: list[_Node] = []

    for item in sorted(items, key=lambda i: i.get("address", "")):
        comp = Component(item.get("address", ""), item.get("type", ""))
        if item.get("mode") == "data":
            out.data.append(comp)
            continue
        provider = provider_short(item.get("provider", ""))
        if provider in HELPER_PROVIDERS:
            out.helpers.append(comp)
            continue
        if provider != "aws":
            out.unmapped.append(_unmapped(item, NON_AWS_PROVIDER, provider or "proveedor desconocido"))
            continue
        if not rmap.usable:
            out.unmapped.append(_unmapped(item, MAP_UNAVAILABLE, "the map could not be loaded"))
            continue
        tf_type = item.get("type", "")
        if tf_type in rmap.invalid:
            out.unmapped.append(_unmapped(item, INVALID_ENTRY, rmap.invalid[tf_type]))
            continue
        entry = rmap.entries.get(tf_type)
        if entry is None:
            out.unmapped.append(_unmapped(item, NO_RULE, "type has no rule in the map"))
            continue
        attrs = item.get("attrs") or {}
        if entry.role == "child":
            children.append(_Node(item, entry))
            continue
        identity = _first(attrs, entry.identity)
        if identity is None or entry.cfn_type is None:
            out.unmapped.append(
                _unmapped(item, MISSING_IDENTITY, f"no usable value in {', '.join(entry.identity)}")
            )
            continue
        key = (entry.cfn_type, identity)
        group = groups.get(key)
        if group is None:
            group = AwsGroup(entry.cfn_type, identity, _display_name(entry, attrs, identity), entry.status)
            groups[key] = group
        elif entry.status == "provisional":
            group.status = "provisional"
        group.primaries.append(Component(comp.address, tf_type, entry.cfn_type))
        registry.setdefault(tf_type, []).append((attrs, group))

    _resolve_children(out, children, registry)
    out.groups = sorted(groups.values(), key=lambda g: (g.cfn_type, g.name, g.identity))
    for g in out.groups:
        g.components.sort(key=lambda c: c.address)
    out.unmapped.sort(key=lambda u: (u.reason, u.address))
    return out
