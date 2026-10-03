"""REST API (FastAPI). Runs in Lambda behind an API Gateway HTTP API via Mangum."""

from __future__ import annotations

import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from typing import Annotated, Any, Literal

from boto3.dynamodb.conditions import Attr, Key
from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse

from terraformation.api import bedrock
from terraformation.api.schemas import (
    ActiveLock,
    ActiveLocks,
    AwsComponent,
    AwsCoverage,
    AwsMapCoverage,
    AwsMapStatus,
    AwsResourceOut,
    AwsResources,
    Dashboard,
    DayActivity,
    DiffSummaryOut,
    DiffSummaryRequest,
    Facets,
    LockHistory,
    LockRecord,
    MapTypeUsage,
    ModuleOut,
    PlanDetail,
    PlanList,
    PlanPayload,
    PlanResource,
    PlanSummary,
    ProjectList,
    ProjectOut,
    SearchHit,
    SearchResult,
    StateDetail,
    StateInfoOut,
    Timeline,
    TimelineEvent,
    UnmappedOut,
    VersionList,
    VersionOut,
)
from terraformation.api.services import Services, decode_cursor, encode_cursor
from terraformation.aws_map.loader import ResourceMap, default_map
from terraformation.aws_map.resolver import Component, Resolution, resolve
from terraformation.diff import diff_states
from terraformation.graph import build_graph
from terraformation.keys import DEFAULT_PATH, StateRef
from terraformation.models import Graph, StateDiff, StateInfo
from terraformation.parser import strip_instance_keys
from terraformation.store import now_iso, plain

AppMode = Literal["main", "plans", "all"]
_services: Services | None = None


def set_services(svc: Services | None) -> None:
    global _services
    _services = svc


def get_services() -> Services:
    if _services is None:  # pragma: no cover - configured in the handler
        raise RuntimeError("servicios no inicializados")
    return _services


Svc = Annotated[Services, Depends(get_services)]
Workspace = Annotated[str, Query(description="Workspace de Terraform")]
StatePath = Annotated[
    str,
    Query(
        description="Path of the state inside the project (includes the file, e.g. `network/prod.tfstate`)"
    ),
]
Limit = Annotated[int, Query(ge=1, le=500)]


def _top(counter: Counter[str], n: int) -> dict[str, int]:
    return dict(counter.most_common(n))


def project_out(svc: Services, s: dict[str, Any], activity: list[int] | None = None) -> ProjectOut:
    return ProjectOut(
        project=s.get("project", ""),
        workspace=s.get("workspace", "default"),
        path=s.get("path", DEFAULT_PATH),
        last_modified=s.get("last_modified"),
        serial=s.get("serial"),
        terraform_version=s.get("terraform_version"),
        lineage=s.get("lineage"),
        resource_count=int(s.get("resource_count", 0)),
        version_count=int(s.get("version_count", 0)),
        current_version_id=s.get("current_version_id"),
        deleted=bool(s.get("deleted", False)),
        lock=svc.lock_out(s),
        activity=activity or [],
        by_type=s.get("by_type", {}),
        by_provider=s.get("by_provider", {}),
        by_module=s.get("by_module", {}),
    )


def _ref(project: str, workspace: str, path: str = DEFAULT_PATH) -> StateRef:
    return StateRef(project, workspace, path)


# ---------------------------------------------------------------------------------------------
# Rutas de lectura
# ---------------------------------------------------------------------------------------------
read = APIRouter(prefix="/api")


@read.get("/projects", response_model=ProjectList, tags=["projects"], summary="Overview de proyectos")
def list_projects(
    svc: Svc,
    q: str | None = None,
    limit: Limit = 200,
    activity: bool = True,
) -> ProjectList:
    """Projects (state = project + workspace) ordered by last modification."""
    items = svc.summaries()
    if q:
        items = [
            i
            for i in items
            if q.lower() in f"{i.get('project', '')}/{i.get('workspace', '')}/{i.get('path', '')}".lower()
        ]
    items = items[:limit]
    acts: list[list[int]] = [[] for _ in items]
    if activity and items:
        with ThreadPoolExecutor(max_workers=8) as pool:
            acts = list(
                pool.map(
                    lambda i: svc.activity(_ref(i["project"], i["workspace"], i.get("path", DEFAULT_PATH))),
                    items,
                )
            )
    return ProjectList(items=[project_out(svc, i, a) for i, a in zip(items, acts, strict=True)])


@read.get("/projects/{project}", response_model=ProjectOut, tags=["projects"], summary="Detalle de proyecto")
def get_project(
    project: str, svc: Svc, workspace: Workspace = "default", path: StatePath = DEFAULT_PATH
) -> ProjectOut:
    ref = _ref(project, workspace, path)
    s = svc.summary(ref)
    cur = svc.store.table.get_item(Key={"PK": ref.pk, "SK": "LOCK#CURRENT"}).get("Item")
    out = project_out(svc, s, svc.activity(ref))
    out.lock = svc.lock_out(s, plain(cur) if cur else None)
    return out


def _version_out(item: dict[str, Any], current: str | None) -> VersionOut:
    return VersionOut(
        version_id=item["version_id"],
        last_modified=item["last_modified"],
        kind=item.get("kind", "state"),
        serial=int(item.get("serial", 0)),
        lineage=item.get("lineage", ""),
        terraform_version=item.get("terraform_version", ""),
        resource_count=int(item.get("resource_count", 0)),
        size=int(item.get("size", 0)),
        added=int(item.get("added", 0)),
        removed=int(item.get("removed", 0)),
        modified=int(item.get("modified", 0)),
        parse_error=item.get("parse_error"),
        is_current=item["version_id"] == current,
    )


@read.get(
    "/projects/{project}/versions",
    response_model=VersionList,
    tags=["projects"],
    summary="Versions of a state",
)
def list_versions(
    project: str,
    svc: Svc,
    workspace: Workspace = "default",
    path: StatePath = DEFAULT_PATH,
    limit: Limit = 100,
) -> VersionList:
    ref = _ref(project, workspace, path)
    current = svc.summary(ref).get("current_version_id")
    versions = plain(svc.store.list_versions(ref))[::-1]
    return VersionList(items=[_version_out(v, current) for v in versions[:limit]])


@read.get("/projects/{project}/timeline", response_model=Timeline, tags=["projects"], summary="Timeline")
def timeline(
    project: str,
    svc: Svc,
    workspace: Workspace = "default",
    path: StatePath = DEFAULT_PATH,
    limit: Limit = 200,
) -> Timeline:
    """Versions with change counts and lock/unlock marks, newest first."""
    ref = _ref(project, workspace, path)
    events: list[TimelineEvent] = []
    for v in plain(svc.store.list_versions(ref)):
        events.append(
            TimelineEvent(
                type="delete_marker" if v.get("kind") == "delete_marker" else "version",
                timestamp=v["last_modified"],
                version_id=v["version_id"],
                serial=int(v.get("serial", 0)),
                terraform_version=v.get("terraform_version", ""),
                resource_count=int(v.get("resource_count", 0)),
                added=int(v.get("added", 0)),
                removed=int(v.get("removed", 0)),
                modified=int(v.get("modified", 0)),
            )
        )
    for lk in plain(svc.store.list_locks(ref)):
        events.append(
            TimelineEvent(
                type="lock_acquired",
                timestamp=lk.get("acquired_s3") or lk.get("acquired_at", ""),
                who=lk.get("who"),
                operation=lk.get("operation"),
                lock_id=lk.get("lock_id"),
            )
        )
        if lk.get("released_at"):
            events.append(
                TimelineEvent(
                    type="lock_released",
                    timestamp=lk["released_at"],
                    who=lk.get("who"),
                    operation=lk.get("operation"),
                    lock_id=lk.get("lock_id"),
                    duration_s=lk.get("duration_s"),
                )
            )
    events.sort(key=lambda e: e.timestamp, reverse=True)
    return Timeline(items=events[:limit])


@read.get(
    "/projects/{project}/versions/{version_id}",
    response_model=StateDetail,
    tags=["states"],
    summary="State detail at a version",
)
def get_state(
    project: str, version_id: str, svc: Svc, workspace: Workspace = "default", path: StatePath = DEFAULT_PATH
) -> StateDetail:
    """Read from S3 by ``versionId`` and masked in memory. ``current`` = current version."""
    ref = _ref(project, workspace, path)
    item = svc.version_item(ref, version_id)
    state = svc.load_state(item)
    mods = Counter(i.module for i in state.instances)
    return StateDetail(
        info=StateInfoOut(
            project=project,
            workspace=workspace,
            path=path,
            version_id=item["version_id"],
            last_modified=item["last_modified"],
            terraform_version=state.terraform_version,
            serial=state.serial,
            lineage=state.lineage,
            resource_count=len(state.instances),
            s3_bucket=item.get("bucket", ""),
            s3_key=item.get("key", ""),
        ),
        outputs=state.outputs,
        modules=[ModuleOut(path=p, resource_count=c) for p, c in sorted(mods.items())],
        resources=state.instances,
    )


def _diff(svc: Services, ref: StateRef, from_version: str, to_version: str) -> StateDiff:
    a, b = svc.version_item(ref, from_version), svc.version_item(ref, to_version)
    old, new = svc.load_state(a), svc.load_state(b)
    return diff_states(
        old,
        new,
        StateInfo(version_id=a["version_id"], last_modified=a["last_modified"]),
        StateInfo(version_id=b["version_id"], last_modified=b["last_modified"]),
    )


@read.get(
    "/projects/{project}/diff",
    response_model=StateDiff,
    response_model_by_alias=True,
    tags=["states"],
    summary="Diff between two versions",
)
def diff(
    project: str,
    svc: Svc,
    from_version: Annotated[str, Query(description="versionId origen")],
    to_version: Annotated[str, Query(description="versionId destino (o `current`)")] = "current",
    workspace: Workspace = "default",
    path: StatePath = DEFAULT_PATH,
) -> StateDiff:
    return _diff(svc, _ref(project, workspace, path), from_version, to_version)


@read.post(
    "/projects/{project}/diff/summary",
    response_model=DiffSummaryOut,
    tags=["states"],
    summary="Resumen en lenguaje natural (Bedrock, opcional)",
)
def diff_summary(project: str, body: DiffSummaryRequest, svc: Svc) -> DiffSummaryOut:
    if not svc.settings.enable_bedrock or svc.bedrock is None:
        raise HTTPException(501, "The Bedrock summary is disabled (EnableBedrockSummary=false)")
    d = _diff(svc, _ref(project, body.workspace, body.path), body.from_version, body.to_version)
    text = bedrock.summarize_diff(svc.bedrock, svc.settings.bedrock_model_id, d, body.language)
    return DiffSummaryOut(summary=text, model_id=svc.settings.bedrock_model_id)


@read.get("/projects/{project}/graph", response_model=Graph, tags=["states"], summary="Grafo de dependencias")
def graph(
    project: str,
    svc: Svc,
    workspace: Workspace = "default",
    path: StatePath = DEFAULT_PATH,
    version: str = "current",
) -> Graph:
    state = svc.load_state(svc.version_item(_ref(project, workspace, path), version))
    return build_graph(state)


@read.get(
    "/projects/{project}/locks", response_model=LockHistory, tags=["locks"], summary="Historial de locks"
)
def project_locks(
    project: str,
    svc: Svc,
    workspace: Workspace = "default",
    path: StatePath = DEFAULT_PATH,
    limit: Limit = 100,
) -> LockHistory:
    ref = _ref(project, workspace, path)
    s = svc.store.get_summary(ref)
    cur = svc.store.table.get_item(Key={"PK": ref.pk, "SK": "LOCK#CURRENT"}).get("Item")
    summary = plain(s) if s else {}
    threshold = svc.settings.lock_alert_minutes * 60
    items: list[LockRecord] = []
    for lk in reversed(plain(svc.store.list_locks(ref))):
        active = not lk.get("released_at")
        started = lk.get("acquired_at") or lk.get("acquired_s3")
        from terraformation.api.services import parse_ts

        t0 = parse_ts(started)
        elapsed = int((svc.now() - t0).total_seconds()) if (t0 and active) else lk.get("duration_s")
        items.append(
            LockRecord(
                lock_id=lk.get("lock_id", ""),
                who=lk.get("who", ""),
                operation=lk.get("operation", ""),
                terraform_version=lk.get("version", ""),
                acquired_at=started or "",
                released_at=lk.get("released_at"),
                duration_s=elapsed,
                active=active,
                alert=active and elapsed is not None and elapsed > threshold,
            )
        )
    return LockHistory(current=svc.lock_out(summary, plain(cur) if cur else None), items=items[:limit])


def _map_status(rmap: ResourceMap) -> AwsMapStatus:
    return AwsMapStatus(
        state=rmap.state,
        stale=rmap.stale,
        reviewed_at=rmap.reviewed_at,
        stale_after_days=rmap.stale_after_days,
        entries=len(rmap.entries),
        issues=rmap.issues[:20],
    )


def _comp(c: Component) -> AwsComponent:
    return AwsComponent(address=c.address, tf_type=c.tf_type, cfn_type=c.cfn_type)


def _resolve_state(svc: Services, ref: StateRef) -> Resolution:
    """Groups the resources of a state. If the map fails, everything stays "unmapped" (fail safe)."""
    return resolve(plain(svc.store.list_resources(ref)), default_map())


@read.get(
    "/projects/{project}/aws-resources",
    response_model=AwsResources,
    tags=["aws-map"],
    summary="AWS resources of a state (Terraform → AWS map)",
)
def aws_resources(
    project: str, svc: Svc, workspace: Workspace = "default", path: StatePath = DEFAULT_PATH
) -> AwsResources:
    """Groups Terraform resources into AWS resources; what the map does not recognize goes in `unmapped`."""
    ref = _ref(project, workspace, path)
    svc.summary(ref)  # 404 if missing
    res = _resolve_state(svc, ref)
    rmap = default_map()
    return AwsResources(
        map=_map_status(rmap),
        coverage=AwsCoverage(**res.coverage()),
        resources=[
            AwsResourceOut(
                cfn_type=g.cfn_type,
                identity=g.identity,
                name=g.name,
                status=g.status,
                primaries=[_comp(c) for c in g.primaries],
                components=[_comp(c) for c in g.components],
            )
            for g in res.groups
        ],
        unmapped=[
            UnmappedOut(
                address=u.address, tf_type=u.tf_type, module=u.module, reason=u.reason, detail=u.detail
            )
            for u in res.unmapped
        ],
        helpers=[_comp(c) for c in res.helpers],
        data=[_comp(c) for c in res.data],
    )


@read.get(
    "/aws-map/coverage",
    response_model=AwsMapCoverage,
    tags=["aws-map"],
    summary="Bucket types the map does not cover yet",
)
def aws_map_coverage(svc: Svc, max_states: Annotated[int, Query(ge=1, le=1000)] = 300) -> AwsMapCoverage:
    """Checks the current states of every project and lists the unmapped types."""
    summaries = [s for s in svc.summaries() if not s.get("deleted")]
    chosen = summaries[:max_states]
    rmap = default_map()
    refs = [_ref(s["project"], s["workspace"], s.get("path", DEFAULT_PATH)) for s in chosen]
    with ThreadPoolExecutor(max_workers=8) as pool:
        resolutions = list(pool.map(lambda r: _resolve_state(svc, r), refs))
    count: Counter[str] = Counter()
    seen_in: dict[str, set[int]] = {}
    reasons: dict[str, Counter[str]] = {}
    info: dict[str, tuple[str | None, str | None]] = {}
    unmapped_total = 0
    for n, res in enumerate(resolutions):
        for g in res.groups:
            for c in [*g.primaries, *g.components]:
                count[c.tf_type] += 1
                seen_in.setdefault(c.tf_type, set()).add(n)
                info.setdefault(c.tf_type, (c.cfn_type, g.status))
        for u in res.unmapped:
            unmapped_total += 1
            count[u.tf_type] += 1
            seen_in.setdefault(u.tf_type, set()).add(n)
            reasons.setdefault(u.tf_type, Counter())[u.reason] += 1
    types = [
        MapTypeUsage(
            tf_type=t,
            count=count[t],
            states=len(seen_in[t]),
            mapped=t not in reasons,
            reason=reasons[t].most_common(1)[0][0] if t in reasons else None,
            cfn_type=info.get(t, (None, None))[0],
            status=info.get(t, (None, None))[1],
        )
        for t in sorted(count, key=lambda x: (x not in reasons, -count[x], x))
    ]
    return AwsMapCoverage(
        map=_map_status(rmap),
        states_checked=len(chosen),
        states_total=len(summaries),
        truncated=len(summaries) > len(chosen),
        resources=sum(count.values()),
        resources_unmapped=unmapped_total,
        types_unmapped=len(reasons),
        types=types,
    )


def _active_locks(svc: Services) -> list[ActiveLock]:
    r = svc.store.table.query(IndexName="GSI2", KeyConditionExpression=Key("GSI2PK").eq("LOCKED"))
    out = []
    for s in plain(r["Items"]):
        lock = svc.lock_out(s)
        out.append(
            ActiveLock(
                project=s["project"],
                workspace=s["workspace"],
                path=s.get("path", DEFAULT_PATH),
                **lock.model_dump(),
            )
        )
    out.sort(key=lambda a: a.since or "")
    return out


@read.get("/locks", response_model=ActiveLocks, tags=["locks"], summary="Currently locked projects")
def active_locks(svc: Svc) -> ActiveLocks:
    return ActiveLocks(threshold_minutes=svc.settings.lock_alert_minutes, items=_active_locks(svc))


@read.get("/dashboard", response_model=Dashboard, tags=["dashboard"], summary="Aggregated metrics")
def dashboard(svc: Svc, days: Annotated[int, Query(ge=1, le=90)] = 30) -> Dashboard:
    summaries = [s for s in svc.summaries() if not s.get("deleted")]
    by_type: Counter[str] = Counter()
    by_provider: Counter[str] = Counter()
    by_module: Counter[str] = Counter()
    by_project: Counter[str] = Counter()
    tf_versions: Counter[str] = Counter()
    for s in summaries:
        by_type.update(s.get("by_type", {}))
        by_provider.update(s.get("by_provider", {}))
        by_module.update(s.get("by_module", {}))
        by_project[s["project"]] += int(s.get("resource_count", 0))
        if s.get("terraform_version"):
            tf_versions[s["terraform_version"]] += 1
    today = svc.now().date()
    start = today - timedelta(days=days - 1)
    r = svc.store.table.query(
        KeyConditionExpression=Key("PK").eq("ACTIVITY")
        & Key("SK").between(f"DAY#{start.isoformat()}", f"DAY#{today.isoformat()}")
    )
    by_day = {i["SK"][4:]: i for i in plain(r["Items"])}
    activity = [
        DayActivity(
            day=(d := (start + timedelta(days=n)).isoformat()),
            versions=int(by_day.get(d, {}).get("versions", 0)),
            locks=int(by_day.get(d, {}).get("locks", 0)),
        )
        for n in range(days)
    ]
    locks = _active_locks(svc)
    return Dashboard(
        projects=len({s["project"] for s in summaries}),
        states=len(summaries),
        resources=sum(int(s.get("resource_count", 0)) for s in summaries),
        versions=sum(int(s.get("version_count", 0)) for s in summaries),
        locked=len(locks),
        lock_alerts=sum(1 for lk in locks if lk.alert),
        lock_threshold_minutes=svc.settings.lock_alert_minutes,
        by_type=_top(by_type, 15),
        by_provider=_top(by_provider, 15),
        by_module=_top(by_module, 15),
        by_project=_top(by_project, 15),
        terraform_versions=dict(tf_versions),
        providers_in_use=sorted(by_provider),
        activity=activity,
        locks=locks,
        recent=[project_out(svc, s) for s in summaries[:8]],
    )


@read.get("/facets", response_model=Facets, tags=["search"], summary="Values for search filters")
def facets(svc: Svc) -> Facets:
    summaries = [s for s in svc.summaries() if not s.get("deleted")]
    types: Counter[str] = Counter()
    providers: Counter[str] = Counter()
    tfv: Counter[str] = Counter()
    for s in summaries:
        types.update(s.get("by_type", {}))
        providers.update(s.get("by_provider", {}))
        if s.get("terraform_version"):
            tfv[s["terraform_version"]] += 1
    return Facets(
        resource_types=dict(sorted(types.items())),
        terraform_versions=dict(sorted(tfv.items())),
        providers=dict(sorted(providers.items())),
        projects=sorted({s["project"] for s in summaries}),
    )


MAX_SCAN_PAGES = 20


@read.get("/search", response_model=SearchResult, tags=["search"], summary="Resource search")
def search(
    svc: Svc,
    type: Annotated[str | None, Query(description="Tipo exacto, p. ej. aws_s3_bucket")] = None,
    name: Annotated[str | None, Query(description="Exact resource name")] = None,
    module: Annotated[str | None, Query(description="Module (contains); `root` = root")] = None,
    project: str | None = None,
    workspace: str | None = None,
    path: Annotated[str | None, Query(description="Exact path of the state inside the project")] = None,
    attribute_key: Annotated[str | None, Query(description="Attribute key (exact or prefix `a.`)")] = None,
    attribute_value: Annotated[str | None, Query(description="Valor de atributo (contiene)")] = None,
    limit: Limit = 100,
    cursor: str | None = None,
) -> SearchResult:
    """Searches the current version of each state.

    * `type` uses GSI1, `name` uses GSI2, `project` queries by key; only with attributes is a
      filtered, bounded Scan done.
    """
    start = decode_cursor(cursor)
    kwargs: dict[str, Any] = {}
    sid_prefix = ""
    if project:
        sid_prefix = f"{project}#{workspace}#" if workspace else f"{project}#"
        if workspace and path:
            sid_prefix += f"{path}#"
    if type:
        kwargs = {"IndexName": "GSI1", "KeyConditionExpression": Key("GSI1PK").eq(f"RTYPE#{type}")}
        if sid_prefix:
            kwargs["KeyConditionExpression"] &= Key("GSI1SK").begins_with(sid_prefix)
        op = "query"
    elif name:
        kwargs = {"IndexName": "GSI2", "KeyConditionExpression": Key("GSI2PK").eq(f"RNAME#{name}")}
        if sid_prefix:
            kwargs["KeyConditionExpression"] &= Key("GSI2SK").begins_with(sid_prefix)
        op = "query"
    elif project and workspace and path:
        ref = _ref(project, workspace, path)
        kwargs = {"KeyConditionExpression": Key("PK").eq(ref.pk) & Key("SK").begins_with("RES#")}
        op = "query"
    else:
        flt: Any = Attr("SK").begins_with("RES#")
        if project:
            flt &= Attr("project").eq(project)
        kwargs = {"FilterExpression": flt}
        op = "scan"

    def matches(item: dict[str, Any]) -> bool:
        if type and item.get("type") != type:
            return False
        if name and item.get("name") != name:
            return False
        if module:
            mod = item.get("module", "root")
            if module == "root":
                if mod != "root":
                    return False
            elif module.lower() not in mod.lower() and module.lower() not in strip_instance_keys(mod).lower():
                return False
        if project and item.get("project") != project:
            return False
        if workspace and item.get("workspace") != workspace:
            return False
        if path and item.get("path", DEFAULT_PATH) != path:
            return False
        if attribute_key or attribute_value:
            attrs = item.get("attrs", {})
            if not any(
                (not attribute_key or k == attribute_key or k.startswith(attribute_key + "."))
                and (not attribute_value or attribute_value.lower() in v.lower())
                for k, v in attrs.items()
            ):
                return False
        return True

    hits: list[SearchHit] = []
    pages = 0
    last_key: dict[str, Any] | None = start
    while True:
        if last_key:
            kwargs["ExclusiveStartKey"] = last_key
        r = getattr(svc.store.table, op)(**kwargs)
        pages += 1
        for item in plain(r["Items"]):
            if not matches(item):
                continue
            attrs = item.get("attrs", {})
            if attribute_key or attribute_value:
                shown = {
                    k: v
                    for k, v in attrs.items()
                    if (not attribute_key or k == attribute_key or k.startswith(attribute_key + "."))
                    and (not attribute_value or attribute_value.lower() in v.lower())
                }
            else:
                shown = {}
            hits.append(
                SearchHit(
                    project=item["project"],
                    workspace=item["workspace"],
                    path=item.get("path", DEFAULT_PATH),
                    address=item["address"],
                    type=item["type"],
                    name=item["name"],
                    module=item.get("module", "root"),
                    provider=item.get("provider", ""),
                    mode=item.get("mode", "managed"),
                    index=item.get("index", ""),
                    attributes=dict(list(shown.items())[:10]),
                )
            )
        last_key = r.get("LastEvaluatedKey")
        if last_key is None or len(hits) >= limit or (op == "scan" and pages >= MAX_SCAN_PAGES):
            break
    return SearchResult(items=hits, cursor=encode_cursor(last_key))


# ---------------------------------------------------------------------------------------------
# Planes (compatibles con terraboard)
# ---------------------------------------------------------------------------------------------
plans_read = APIRouter(prefix="/api")
plans_write = APIRouter(prefix="/api")

_ACTION_KEY = {
    ("no-op",): "no-op",
    ("create",): "create",
    ("read",): "read",
    ("update",): "update",
    ("delete",): "delete",
    ("delete", "create"): "replace",
    ("create", "delete"): "replace",
}
MAX_PLAN_RESOURCES = 1500


def summarize_plan(
    plan: dict[str, Any],
) -> tuple[dict[str, int], list[PlanResource], list[PlanResource], dict[str, str], bool]:
    counts: Counter[str] = Counter()
    resources: list[PlanResource] = []
    truncated = False
    for rc in plan.get("resource_changes") or []:
        actions = list(rc.get("change", {}).get("actions", []))
        counts[_ACTION_KEY.get(tuple(actions), "other")] += 1
        if actions == ["no-op"]:
            continue
        if len(resources) >= MAX_PLAN_RESOURCES:
            truncated = True
            continue
        resources.append(
            PlanResource(address=rc.get("address", ""), type=rc.get("type", ""), actions=actions)
        )
    outputs = [
        PlanResource(address=name, actions=list(ch.get("actions", [])))
        for name, ch in sorted((plan.get("output_changes") or {}).items())
        if list(ch.get("actions", [])) != ["no-op"]
    ]
    constraints = {
        str(v.get("full_name") or k): str(v.get("version_constraint", ""))
        for k, v in ((plan.get("configuration") or {}).get("provider_config") or {}).items()
        if isinstance(v, dict)
    }
    return dict(counts), resources, outputs, constraints, truncated


def _plan_summary(item: dict[str, Any]) -> PlanSummary:
    return PlanSummary(
        id=item["SK"].removeprefix("PLAN#"),
        lineage=item["PK"].removeprefix("LINEAGE#"),
        created_at=item.get("created_at", ""),
        terraform_version=item.get("terraform_version", ""),
        git_remote=item.get("git_remote", ""),
        git_commit=item.get("git_commit", ""),
        ci_url=item.get("ci_url", ""),
        source=item.get("source", ""),
        counts=item.get("counts", {}),
        exit_code=int(item.get("exit_code", 0)),
    )


@plans_write.post(
    "/plans", response_model=PlanSummary, status_code=201, tags=["plans"], summary="Enviar un plan"
)
def submit_plan(payload: PlanPayload, svc: Svc) -> PlanSummary:
    """Same payload as terraboard. A change summary is stored, not the raw JSON."""
    counts, resources, outputs, constraints, truncated = summarize_plan(payload.plan_json)
    created = now_iso()
    plan_id = f"{created}_{uuid.uuid4().hex[:12]}"
    changed = any(v for k, v in counts.items() if k not in {"no-op", "read"})
    item = {
        "PK": f"LINEAGE#{payload.lineage}",
        "SK": f"PLAN#{plan_id}",
        "created_at": created,
        "terraform_version": payload.terraform_version or str(payload.plan_json.get("terraform_version", "")),
        "git_remote": payload.git_remote,
        "git_commit": payload.git_commit,
        "ci_url": payload.ci_url,
        "source": payload.source,
        "counts": counts,
        "exit_code": 2 if changed else 0,
        "resources": [r.model_dump() for r in resources],
        "outputs": [o.model_dump() for o in outputs],
        "provider_constraints": constraints,
        "truncated": truncated,
    }
    svc.store.table.put_item(Item=item)
    return _plan_summary(item)


@plans_read.get("/plans", response_model=PlanList, tags=["plans"], summary="Plans of a lineage or project")
def list_plans(
    svc: Svc,
    lineage: str | None = None,
    project: str | None = None,
    workspace: str = "default",
    path: str = DEFAULT_PATH,
    limit: Limit = 50,
) -> PlanList:
    if not lineage and project:
        lineage = str(svc.summary(_ref(project, workspace, path)).get("lineage", ""))
    if not lineage:
        raise HTTPException(400, "indica `lineage` o `project`")
    r = svc.store.table.query(
        KeyConditionExpression=Key("PK").eq(f"LINEAGE#{lineage}") & Key("SK").begins_with("PLAN#"),
        ScanIndexForward=False,
        Limit=limit,
    )
    return PlanList(items=[_plan_summary(plain(i)) for i in r["Items"]])


@plans_read.get(
    "/plans/{lineage}/{plan_id}", response_model=PlanDetail, tags=["plans"], summary="Detalle de un plan"
)
def get_plan(lineage: str, plan_id: str, svc: Svc) -> PlanDetail:
    item = svc.store.table.get_item(Key={"PK": f"LINEAGE#{lineage}", "SK": f"PLAN#{plan_id}"}).get("Item")
    if not item:
        raise HTTPException(404, "plan no encontrado")
    item = plain(item)
    return PlanDetail(
        **_plan_summary(item).model_dump(),
        resources=[PlanResource(**r) for r in item.get("resources", [])],
        outputs=[PlanResource(**r) for r in item.get("outputs", [])],
        provider_constraints=item.get("provider_constraints", {}),
        truncated=bool(item.get("truncated", False)),
    )


# ---------------------------------------------------------------------------------------------
def create_app(mode: AppMode = "main") -> FastAPI:
    app = FastAPI(
        title="Terraformation API",
        version="0.1.0",
        description="Read-only API to visualize Terraform states stored in S3.",
        docs_url=None,
        redoc_url=None,
        openapi_url="/api/openapi.json" if mode == "all" else None,
    )
    if mode in {"main", "all"}:
        app.include_router(read)
        app.include_router(plans_read)
    if mode in {"plans", "all"}:
        app.include_router(plans_write)

    @app.exception_handler(HTTPException)
    async def _http(_: Any, exc: HTTPException) -> JSONResponse:
        return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)

    return app
