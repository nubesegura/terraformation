"""Diff entre dos versiones de un mismo state."""

from __future__ import annotations

import difflib

from terraformation.models import (
    AttrChange,
    DiffCounts,
    Instance,
    OutputChange,
    ParsedState,
    ResourceChange,
    ResourceModified,
    StateDiff,
    StateInfo,
)

MAX_ATTRS_LISTED = 200


def format_resource(inst: Instance) -> str:
    lines = [f'resource "{inst.type}" "{inst.name}" {{']
    lines += [f'  {k} = "{v}"' for k, v in sorted(inst.attributes.items())]
    lines.append("}")
    return "\n".join(lines) + "\n"


def _change(inst: Instance) -> ResourceChange:
    attrs = dict(sorted(inst.attributes.items())[:MAX_ATTRS_LISTED])
    return ResourceChange(
        address=inst.address, type=inst.type, name=inst.name, module=inst.module, attributes=attrs
    )


def diff_resource(old: Instance, new: Instance, from_label: str, to_label: str) -> ResourceModified | None:
    changes: list[AttrChange] = []
    for key in sorted(set(old.attributes) | set(new.attributes)):
        a, b = old.attributes.get(key), new.attributes.get(key)
        if a == b:
            continue
        kind = "added" if a is None else "removed" if b is None else "changed"
        changes.append(AttrChange(key=key, kind=kind, old=a, new=b))
    deps_changed = old.dependencies != new.dependencies
    sens = bool(old.raw_digest) and old.raw_digest != new.raw_digest and not changes
    if not changes and not deps_changed and not sens and old.status == new.status:
        return None
    unified = "".join(
        difflib.unified_diff(
            format_resource(old).splitlines(keepends=True),
            format_resource(new).splitlines(keepends=True),
            fromfile=from_label,
            tofile=to_label,
            n=3,
        )
    )
    return ResourceModified(
        address=new.address,
        type=new.type,
        name=new.name,
        module=new.module,
        changes=changes,
        sensitive_changed=sens,
        dependencies_changed=deps_changed,
        unified_diff=unified,
    )


def diff_states(
    old: ParsedState,
    new: ParsedState,
    old_info: StateInfo | None = None,
    new_info: StateInfo | None = None,
) -> StateDiff:
    o = {i.address: i for i in old.instances}
    n = {i.address: i for i in new.instances}
    old_info = old_info or StateInfo()
    new_info = new_info or StateInfo()
    old_info = old_info.model_copy(
        update={
            "terraform_version": old.terraform_version,
            "serial": old.serial,
            "resource_count": len(o),
        }
    )
    new_info = new_info.model_copy(
        update={
            "terraform_version": new.terraform_version,
            "serial": new.serial,
            "resource_count": len(n),
        }
    )
    added = [_change(n[a]) for a in sorted(n.keys() - o.keys())]
    removed = [_change(o[a]) for a in sorted(o.keys() - n.keys())]
    modified: list[ResourceModified] = []
    unchanged = 0
    for a in sorted(o.keys() & n.keys()):
        m = diff_resource(o[a], n[a], f"{a} ({old_info.version_id})", f"{a} ({new_info.version_id})")
        if m is None:
            unchanged += 1
        else:
            modified.append(m)
    return StateDiff(
        **{"from": old_info},
        to=new_info,
        summary=DiffCounts(
            added=len(added), removed=len(removed), modified=len(modified), unchanged=unchanged
        ),
        added=added,
        removed=removed,
        modified=modified,
        outputs=_diff_outputs(old, new),
    )


def _diff_outputs(old: ParsedState, new: ParsedState) -> list[OutputChange]:
    o = {x.name: x for x in old.outputs}
    n = {x.name: x for x in new.outputs}
    out: list[OutputChange] = []
    for name in sorted(o.keys() | n.keys()):
        a, b = o.get(name), n.get(name)
        if a is None and b is not None:
            out.append(OutputChange(name=name, kind="added", new=b.value))
        elif b is None and a is not None:
            out.append(OutputChange(name=name, kind="removed", old=a.value))
        elif a is not None and b is not None and (a.value != b.value or a.sensitive != b.sensitive):
            out.append(OutputChange(name=name, kind="changed", old=a.value, new=b.value))
    return out


def count_changes(old: ParsedState | None, new: ParsedState) -> tuple[int, int, int]:
    """(agregados, eliminados, modificados) de ``new`` respecto a ``old`` (sin texto de diff)."""
    if old is None:
        return len(new.instances), 0, 0
    o = {i.address: i for i in old.instances}
    n = {i.address: i for i in new.instances}
    modified = sum(
        1
        for a in o.keys() & n.keys()
        if o[a].attributes != n[a].attributes
        or o[a].dependencies != n[a].dependencies
        or o[a].raw_digest != n[a].raw_digest
    )
    return len(n.keys() - o.keys()), len(o.keys() - n.keys()), modified
