"""Grafo de dependencias entre recursos y entre módulos."""

from __future__ import annotations

from terraformation.models import Graph, GraphEdge, GraphNode, ModuleEdge, ParsedState
from terraformation.parser import strip_instance_keys


def _module_of(address: str) -> str:
    """Módulo (sin claves) de una dirección de recurso/módulo."""
    parts = strip_instance_keys(address).split(".")
    mod: list[str] = []
    i = 0
    while i + 1 < len(parts) and parts[i] == "module":
        mod += parts[i : i + 2]
        i += 2
    return ".".join(mod) if mod else "root"


def build_graph(state: ParsedState) -> Graph:
    nodes: dict[str, GraphNode] = {}
    for inst in state.instances:
        node = nodes.get(inst.base_address)
        if node:
            node.instances += 1
            continue
        nodes[inst.base_address] = GraphNode(
            id=inst.base_address,
            kind="data" if inst.mode == "data" else "resource",
            type=inst.type,
            name=inst.name,
            module=inst.module_base,
            provider=inst.provider,
        )
    edges: set[tuple[str, str]] = set()
    for inst in state.instances:
        for dep in inst.dependencies:
            target = strip_instance_keys(dep)
            if target not in nodes:
                if not target.startswith("module."):
                    continue  # referencia a algo que no está en el state
                nodes[target] = GraphNode(id=target, kind="module", name=target, module=_module_of(target))
            if target != inst.base_address:
                edges.add((inst.base_address, target))
    module_counts: dict[tuple[str, str], int] = {}
    for src, dst in edges:
        a, b = nodes[src].module, nodes[dst].module
        if nodes[dst].kind == "module":
            b = dst
        if a != b:
            module_counts[(a, b)] = module_counts.get((a, b), 0) + 1
    return Graph(
        nodes=sorted(nodes.values(), key=lambda n: n.id),
        edges=[GraphEdge(source=s, target=t) for s, t in sorted(edges)],
        module_edges=[ModuleEdge(source=s, target=t, count=c) for (s, t), c in sorted(module_counts.items())],
    )
