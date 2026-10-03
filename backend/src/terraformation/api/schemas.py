"""Esquemas de la API (contrato OpenAPI generado por FastAPI)."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

from terraformation.models import Graph, Instance, Output, StateDiff

LockStatus = Literal["locked", "released", "none_detected"]


class LockOut(BaseModel):
    status: LockStatus = Field(description="locked | released | none_detected (nunca se vio un .tflock)")
    who: str = ""
    operation: str = ""
    lock_id: str = ""
    since: str | None = Field(default=None, description="Inicio del lock activo (Created del .tflock)")
    released_at: str | None = None
    duration_s: int | None = Field(default=None, description="Segundos bloqueado hasta ahora")
    alert: bool = Field(default=False, description="Lock activo por más del umbral configurado")


class ProjectOut(BaseModel):
    project: str
    workspace: str
    path: str = "terraform.tfstate"
    last_modified: str | None = None
    serial: int | None = None
    terraform_version: str | None = None
    lineage: str | None = None
    resource_count: int = 0
    version_count: int = 0
    current_version_id: str | None = None
    deleted: bool = False
    lock: LockOut
    activity: list[int] = Field(default_factory=list, description="Versiones por día, últimos 14 días")
    by_type: dict[str, int] = Field(default_factory=dict)
    by_provider: dict[str, int] = Field(default_factory=dict)
    by_module: dict[str, int] = Field(default_factory=dict)


class Page(BaseModel):
    cursor: str | None = Field(default=None, description="Cursor opaco para la página siguiente")


class ProjectList(Page):
    items: list[ProjectOut]


class VersionOut(BaseModel):
    version_id: str
    last_modified: str
    kind: Literal["state", "delete_marker"] = "state"
    serial: int = 0
    lineage: str = ""
    terraform_version: str = ""
    resource_count: int = 0
    size: int = 0
    added: int = 0
    removed: int = 0
    modified: int = 0
    parse_error: str | None = None
    is_current: bool = False


class VersionList(Page):
    items: list[VersionOut]


class TimelineEvent(BaseModel):
    type: Literal["version", "delete_marker", "lock_acquired", "lock_released"]
    timestamp: str
    version_id: str | None = None
    serial: int | None = None
    terraform_version: str | None = None
    resource_count: int | None = None
    added: int | None = None
    removed: int | None = None
    modified: int | None = None
    who: str | None = None
    operation: str | None = None
    lock_id: str | None = None
    duration_s: int | None = None


class Timeline(BaseModel):
    items: list[TimelineEvent]


class LockRecord(BaseModel):
    lock_id: str
    who: str
    operation: str
    terraform_version: str = ""
    acquired_at: str
    released_at: str | None = None
    duration_s: int | None = None
    active: bool = False
    alert: bool = False


class LockHistory(BaseModel):
    current: LockOut
    items: list[LockRecord]


class ActiveLock(LockOut):
    project: str
    workspace: str
    path: str = "terraform.tfstate"


class ActiveLocks(BaseModel):
    threshold_minutes: int
    items: list[ActiveLock]


class ModuleOut(BaseModel):
    path: str
    resource_count: int


class StateInfoOut(BaseModel):
    project: str
    workspace: str
    path: str = "terraform.tfstate"
    version_id: str
    last_modified: str
    terraform_version: str
    serial: int
    lineage: str
    resource_count: int
    s3_bucket: str
    s3_key: str


class StateDetail(BaseModel):
    info: StateInfoOut
    outputs: list[Output]
    modules: list[ModuleOut]
    resources: list[Instance]


class SearchHit(BaseModel):
    project: str
    workspace: str
    path: str = "terraform.tfstate"
    address: str
    type: str
    name: str
    module: str
    provider: str
    mode: str
    index: str = ""
    attributes: dict[str, str] = Field(default_factory=dict)


class SearchResult(Page):
    items: list[SearchHit]


class DayActivity(BaseModel):
    day: str
    versions: int = 0
    locks: int = 0


class Dashboard(BaseModel):
    projects: int
    states: int
    resources: int
    versions: int
    locked: int
    lock_alerts: int
    lock_threshold_minutes: int
    by_type: dict[str, int]
    by_provider: dict[str, int]
    by_module: dict[str, int]
    by_project: dict[str, int]
    terraform_versions: dict[str, int]
    providers_in_use: list[str]
    activity: list[DayActivity]
    locks: list[ActiveLock]
    recent: list[ProjectOut]


class Facets(BaseModel):
    resource_types: dict[str, int]
    terraform_versions: dict[str, int]
    providers: dict[str, int]
    projects: list[str]


class DiffSummaryRequest(BaseModel):
    workspace: str = "default"
    path: str = "terraform.tfstate"
    from_version: str
    to_version: str
    language: str = "es"


class DiffSummaryOut(BaseModel):
    summary: str
    model_id: str


class PlanPayload(BaseModel):
    """Mismo payload que Terraboard (POST /api/plans)."""

    lineage: str
    terraform_version: str = ""
    git_remote: str = ""
    git_commit: str = ""
    ci_url: str = ""
    source: str = ""
    plan_json: dict[str, Any] = Field(default_factory=dict)


class PlanResource(BaseModel):
    address: str
    type: str = ""
    actions: list[str]


class PlanSummary(BaseModel):
    id: str
    lineage: str
    created_at: str
    terraform_version: str = ""
    git_remote: str = ""
    git_commit: str = ""
    ci_url: str = ""
    source: str = ""
    counts: dict[str, int] = Field(default_factory=dict)
    exit_code: int = Field(default=0, description="2 si el plan contiene cambios, 0 si no")


class PlanDetail(PlanSummary):
    resources: list[PlanResource] = Field(default_factory=list)
    outputs: list[PlanResource] = Field(default_factory=list)
    provider_constraints: dict[str, str] = Field(default_factory=dict)
    truncated: bool = False


class PlanList(Page):
    items: list[PlanSummary]


class Problem(BaseModel):
    detail: str


__all__ = [
    "Graph",
    "StateDiff",
]


# ---- Recursos AWS (mapa Terraform -> AWS) --------------------------------------------------
class AwsMapStatus(BaseModel):
    state: Literal["ok", "degraded", "unavailable"]
    stale: bool = Field(description="El mapa lleva más de `stale_after_days` sin revisarse (solo aviso)")
    reviewed_at: str | None = None
    stale_after_days: int
    entries: int
    issues: list[str] = Field(default_factory=list)


class AwsComponent(BaseModel):
    address: str
    tf_type: str
    cfn_type: str | None = Field(
        default=None, description="Tipo de CloudFormation equivalente, si el mapa lo indica"
    )


class AwsResourceOut(BaseModel):
    cfn_type: str
    identity: str
    name: str
    status: Literal["verified", "provisional"]
    primaries: list[AwsComponent]
    components: list[AwsComponent]


class UnmappedOut(BaseModel):
    address: str
    tf_type: str
    module: str = "root"
    reason: str = Field(
        description=(
            "no_rule | non_aws_provider | missing_identity | missing_parent_ref | "
            "orphan_child | ambiguous_parent | invalid_map_entry | map_unavailable"
        )
    )
    detail: str = ""


class AwsCoverage(BaseModel):
    managed_total: int
    mapped: int
    unmapped: int
    percent: float
    aws_resources: int
    unmapped_by_reason: dict[str, int]


class AwsResources(BaseModel):
    map: AwsMapStatus
    coverage: AwsCoverage
    resources: list[AwsResourceOut]
    unmapped: list[UnmappedOut]
    helpers: list[AwsComponent]
    data: list[AwsComponent]


class MapTypeUsage(BaseModel):
    tf_type: str
    count: int = Field(description="Instancias de este tipo en todos los states revisados")
    states: int = Field(description="States distintos donde aparece")
    mapped: bool
    reason: str | None = Field(
        default=None, description="Motivo de 'sin mapear' más frecuente (si no está mapeado)"
    )
    cfn_type: str | None = None
    status: str | None = None


class AwsMapCoverage(BaseModel):
    map: AwsMapStatus
    states_checked: int
    states_total: int
    truncated: bool = Field(description="Hay más states que `max_states`: la cobertura es parcial")
    resources: int
    resources_unmapped: int
    types_unmapped: int
    types: list[MapTypeUsage]
