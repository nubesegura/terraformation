"""Pydantic domain models (parsed state, summary, diff, graph, locks)."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class Output(BaseModel):
    name: str
    sensitive: bool = False
    type: str = ""
    value: str = ""


class Instance(BaseModel):
    """A resource instance (``count``/``for_each`` produce several)."""

    model_config = ConfigDict(extra="forbid")

    address: str
    base_address: str
    module: str = "root"
    mode: Literal["managed", "data"] = "managed"
    type: str
    name: str
    index: str | None = None
    provider: str = ""
    status: str | None = None
    deposed: str | None = None
    attributes: dict[str, str] = Field(default_factory=dict)
    dependencies: list[str] = Field(default_factory=list)
    # In memory only: detects changes in masked values. Never persisted.
    raw_digest: str = Field(default="", exclude=True, repr=False)

    @property
    def module_base(self) -> str:
        from terraformation.parser import strip_instance_keys

        return strip_instance_keys(self.module)


class ParsedState(BaseModel):
    terraform_version: str = ""
    serial: int = 0
    lineage: str = ""
    outputs: list[Output] = Field(default_factory=list)
    instances: list[Instance] = Field(default_factory=list)


class StateSummary(BaseModel):
    resource_count: int = 0
    by_type: dict[str, int] = Field(default_factory=dict)
    by_provider: dict[str, int] = Field(default_factory=dict)
    by_module: dict[str, int] = Field(default_factory=dict)


class AttrChange(BaseModel):
    key: str
    kind: Literal["added", "removed", "changed"]
    old: str | None = None
    new: str | None = None


class ResourceChange(BaseModel):
    address: str
    type: str
    name: str
    module: str
    attributes: dict[str, str] = Field(default_factory=dict)


class ResourceModified(ResourceChange):
    changes: list[AttrChange] = Field(default_factory=list)
    sensitive_changed: bool = False
    dependencies_changed: bool = False
    unified_diff: str = ""


class OutputChange(BaseModel):
    name: str
    kind: Literal["added", "removed", "changed"]
    old: str | None = None
    new: str | None = None


class StateInfo(BaseModel):
    version_id: str = ""
    last_modified: str = ""
    terraform_version: str = ""
    serial: int = 0
    resource_count: int = 0


class DiffCounts(BaseModel):
    added: int = 0
    removed: int = 0
    modified: int = 0
    unchanged: int = 0


class StateDiff(BaseModel):
    from_: StateInfo = Field(alias="from")
    to: StateInfo
    summary: DiffCounts
    added: list[ResourceChange] = Field(default_factory=list)
    removed: list[ResourceChange] = Field(default_factory=list)
    modified: list[ResourceModified] = Field(default_factory=list)
    outputs: list[OutputChange] = Field(default_factory=list)

    model_config = ConfigDict(populate_by_name=True)


class GraphNode(BaseModel):
    id: str
    kind: Literal["resource", "data", "module"]
    type: str = ""
    name: str = ""
    module: str = "root"
    provider: str = ""
    instances: int = 1


class GraphEdge(BaseModel):
    source: str
    target: str


class ModuleEdge(BaseModel):
    source: str
    target: str
    count: int


class Graph(BaseModel):
    nodes: list[GraphNode] = Field(default_factory=list)
    edges: list[GraphEdge] = Field(default_factory=list)
    module_edges: list[ModuleEdge] = Field(default_factory=list)


class LockInfo(BaseModel):
    """JSON of the native S3 ``.tflock`` (fields as Terraform writes them)."""

    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    id: str = Field(default="", alias="ID")
    operation: str = Field(default="", alias="Operation")
    info: str = Field(default="", alias="Info")
    who: str = Field(default="", alias="Who")
    version: str = Field(default="", alias="Version")
    created: str = Field(default="", alias="Created")
    path: str = Field(default="", alias="Path")
