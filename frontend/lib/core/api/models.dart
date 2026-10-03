// Modelos tipados alineados con docs/openapi.yaml.
// Cada clase indica su esquema con `// openapi: <Schema>`; scripts/check_dart_models.py
// verifica en CI que los campos coincidan con el contrato.

import '../state_ref.dart';

typedef Json = Map<String, dynamic>;

String _s(Json j, String k, [String d = '']) => (j[k] as String?) ?? d;
String? _sn(Json j, String k) => j[k] as String?;
int _i(Json j, String k, [int d = 0]) => (j[k] as num?)?.toInt() ?? d;
int? _in(Json j, String k) => (j[k] as num?)?.toInt();
bool _b(Json j, String k, [bool d = false]) => (j[k] as bool?) ?? d;
List<T> _l<T>(Json j, String k, T Function(Json) f) =>
    ((j[k] as List?) ?? const []).map((e) => f(e as Json)).toList();
Map<String, int> _mi(Json j, String k) =>
    ((j[k] as Map?) ?? const {}).map((a, b) => MapEntry(a as String, (b as num).toInt()));
Map<String, String> _ms(Json j, String k) =>
    ((j[k] as Map?) ?? const {}).map((a, b) => MapEntry(a as String, '$b'));

// openapi: LockOut
class LockInfo {
  const LockInfo({
    required this.status,
    this.who = '',
    this.operation = '',
    this.lockId = '',
    this.since,
    this.releasedAt,
    this.durationS,
    this.alert = false,
  });

  /// locked | released | none_detected
  final String status;
  final String who;
  final String operation;
  final String lockId;
  final String? since;
  final String? releasedAt;
  final int? durationS;
  final bool alert;

  bool get isLocked => status == 'locked';
  bool get noneDetected => status == 'none_detected';

  factory LockInfo.fromJson(Json j) => LockInfo(
        status: _s(j, 'status', 'none_detected'),
        who: _s(j, 'who'),
        operation: _s(j, 'operation'),
        lockId: _s(j, 'lock_id'),
        since: _sn(j, 'since'),
        releasedAt: _sn(j, 'released_at'),
        durationS: _in(j, 'duration_s'),
        alert: _b(j, 'alert'),
      );
}

// openapi: ActiveLock
class ActiveLock extends LockInfo {
  const ActiveLock({
    required this.project,
    required this.workspace,
    this.path = 'terraform.tfstate',
    required super.status,
    super.who,
    super.operation,
    super.lockId,
    super.since,
    super.releasedAt,
    super.durationS,
    super.alert,
  });

  final String project;
  final String workspace;
  final String path;

  StateRef get stateRef => (project: project, workspace: workspace, path: path);

  factory ActiveLock.fromJson(Json j) {
    final base = LockInfo.fromJson(j);
    return ActiveLock(
      project: _s(j, 'project'),
      workspace: _s(j, 'workspace', 'default'),
      path: _s(j, 'path', 'terraform.tfstate'),
      status: _s(j, 'status', 'none_detected'),
      who: base.who,
      operation: base.operation,
      lockId: base.lockId,
      since: base.since,
      releasedAt: base.releasedAt,
      durationS: base.durationS,
      alert: base.alert,
    );
  }
}

// openapi: ActiveLocks
class ActiveLocks {
  const ActiveLocks({required this.thresholdMinutes, required this.items});
  final int thresholdMinutes;
  final List<ActiveLock> items;

  factory ActiveLocks.fromJson(Json j) => ActiveLocks(
        thresholdMinutes: _i(j, 'threshold_minutes', 30),
        items: _l(j, 'items', ActiveLock.fromJson),
      );
}

// openapi: ProjectOut
class Project {
  const Project({
    required this.project,
    required this.workspace,
    required this.lock,
    this.path = 'terraform.tfstate',
    this.lastModified,
    this.serial,
    this.terraformVersion,
    this.lineage,
    this.resourceCount = 0,
    this.versionCount = 0,
    this.currentVersionId,
    this.deleted = false,
    this.activity = const [],
    this.byType = const {},
    this.byProvider = const {},
    this.byModule = const {},
  });

  final String project;
  final String workspace;
  final String path;
  final String? lastModified;
  final int? serial;
  final String? terraformVersion;
  final String? lineage;
  final int resourceCount;
  final int versionCount;
  final String? currentVersionId;
  final bool deleted;
  final LockInfo lock;
  final List<int> activity;
  final Map<String, int> byType;
  final Map<String, int> byProvider;
  final Map<String, int> byModule;

  StateRef get stateRef => (project: project, workspace: workspace, path: path);

  /// Nombre corto del state dentro del proyecto (`terraform.tfstate` se omite).
  String get statePath => path == 'terraform.tfstate' ? '' : path;

  String get label {
    final ws = workspace == 'default' ? '' : ':$workspace';
    return statePath.isEmpty ? '$project$ws' : '$project$ws/$statePath';
  }

  factory Project.fromJson(Json j) => Project(
        project: _s(j, 'project'),
        workspace: _s(j, 'workspace', 'default'),
        path: _s(j, 'path', 'terraform.tfstate'),
        lastModified: _sn(j, 'last_modified'),
        serial: _in(j, 'serial'),
        terraformVersion: _sn(j, 'terraform_version'),
        lineage: _sn(j, 'lineage'),
        resourceCount: _i(j, 'resource_count'),
        versionCount: _i(j, 'version_count'),
        currentVersionId: _sn(j, 'current_version_id'),
        deleted: _b(j, 'deleted'),
        lock: LockInfo.fromJson((j['lock'] as Json?) ?? const {'status': 'none_detected'}),
        activity: ((j['activity'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        byType: _mi(j, 'by_type'),
        byProvider: _mi(j, 'by_provider'),
        byModule: _mi(j, 'by_module'),
      );
}

// openapi: ProjectList
class ProjectList {
  const ProjectList(this.items);
  final List<Project> items;
  factory ProjectList.fromJson(Json j) => ProjectList(_l(j, 'items', Project.fromJson));
}

// openapi: VersionOut
class VersionInfo {
  const VersionInfo({
    required this.versionId,
    required this.lastModified,
    this.kind = 'state',
    this.serial = 0,
    this.lineage = '',
    this.terraformVersion = '',
    this.resourceCount = 0,
    this.size = 0,
    this.added = 0,
    this.removed = 0,
    this.modified = 0,
    this.parseError,
    this.isCurrent = false,
  });

  final String versionId;
  final String lastModified;
  final String kind;
  final int serial;
  final String lineage;
  final String terraformVersion;
  final int resourceCount;
  final int size;
  final int added;
  final int removed;
  final int modified;
  final String? parseError;
  final bool isCurrent;

  bool get readable => kind == 'state' && parseError == null;

  factory VersionInfo.fromJson(Json j) => VersionInfo(
        versionId: _s(j, 'version_id'),
        lastModified: _s(j, 'last_modified'),
        kind: _s(j, 'kind', 'state'),
        serial: _i(j, 'serial'),
        lineage: _s(j, 'lineage'),
        terraformVersion: _s(j, 'terraform_version'),
        resourceCount: _i(j, 'resource_count'),
        size: _i(j, 'size'),
        added: _i(j, 'added'),
        removed: _i(j, 'removed'),
        modified: _i(j, 'modified'),
        parseError: _sn(j, 'parse_error'),
        isCurrent: _b(j, 'is_current'),
      );
}

// openapi: VersionList
class VersionList {
  const VersionList(this.items);
  final List<VersionInfo> items;
  factory VersionList.fromJson(Json j) => VersionList(_l(j, 'items', VersionInfo.fromJson));
}

// openapi: TimelineEvent
class TimelineEvent {
  const TimelineEvent({
    required this.type,
    required this.timestamp,
    this.versionId,
    this.serial,
    this.terraformVersion,
    this.resourceCount,
    this.added,
    this.removed,
    this.modified,
    this.who,
    this.operation,
    this.lockId,
    this.durationS,
  });

  /// version | delete_marker | lock_acquired | lock_released
  final String type;
  final String timestamp;
  final String? versionId;
  final int? serial;
  final String? terraformVersion;
  final int? resourceCount;
  final int? added;
  final int? removed;
  final int? modified;
  final String? who;
  final String? operation;
  final String? lockId;
  final int? durationS;

  factory TimelineEvent.fromJson(Json j) => TimelineEvent(
        type: _s(j, 'type'),
        timestamp: _s(j, 'timestamp'),
        versionId: _sn(j, 'version_id'),
        serial: _in(j, 'serial'),
        terraformVersion: _sn(j, 'terraform_version'),
        resourceCount: _in(j, 'resource_count'),
        added: _in(j, 'added'),
        removed: _in(j, 'removed'),
        modified: _in(j, 'modified'),
        who: _sn(j, 'who'),
        operation: _sn(j, 'operation'),
        lockId: _sn(j, 'lock_id'),
        durationS: _in(j, 'duration_s'),
      );
}

// openapi: Timeline
class Timeline {
  const Timeline(this.items);
  final List<TimelineEvent> items;
  factory Timeline.fromJson(Json j) => Timeline(_l(j, 'items', TimelineEvent.fromJson));
}

// openapi: LockRecord
class LockRecord {
  const LockRecord({
    required this.lockId,
    required this.who,
    required this.operation,
    required this.acquiredAt,
    this.terraformVersion = '',
    this.releasedAt,
    this.durationS,
    this.active = false,
    this.alert = false,
  });

  final String lockId;
  final String who;
  final String operation;
  final String terraformVersion;
  final String acquiredAt;
  final String? releasedAt;
  final int? durationS;
  final bool active;
  final bool alert;

  factory LockRecord.fromJson(Json j) => LockRecord(
        lockId: _s(j, 'lock_id'),
        who: _s(j, 'who'),
        operation: _s(j, 'operation'),
        terraformVersion: _s(j, 'terraform_version'),
        acquiredAt: _s(j, 'acquired_at'),
        releasedAt: _sn(j, 'released_at'),
        durationS: _in(j, 'duration_s'),
        active: _b(j, 'active'),
        alert: _b(j, 'alert'),
      );
}

// openapi: LockHistory
class LockHistory {
  const LockHistory({required this.current, required this.items});
  final LockInfo current;
  final List<LockRecord> items;
  factory LockHistory.fromJson(Json j) => LockHistory(
        current: LockInfo.fromJson(j['current'] as Json),
        items: _l(j, 'items', LockRecord.fromJson),
      );
}

// openapi: Output
class StateOutput {
  const StateOutput({required this.name, this.sensitive = false, this.type = '', this.value = ''});
  final String name;
  final bool sensitive;
  final String type;
  final String value;
  factory StateOutput.fromJson(Json j) => StateOutput(
        name: _s(j, 'name'),
        sensitive: _b(j, 'sensitive'),
        type: _s(j, 'type'),
        value: _s(j, 'value'),
      );
}

// openapi: Instance
class ResourceInstance {
  const ResourceInstance({
    required this.address,
    required this.baseAddress,
    required this.type,
    required this.name,
    this.module = 'root',
    this.mode = 'managed',
    this.index,
    this.provider = '',
    this.status,
    this.deposed,
    this.attributes = const {},
    this.dependencies = const [],
  });

  final String address;
  final String baseAddress;
  final String module;
  final String mode;
  final String type;
  final String name;
  final String? index;
  final String provider;
  final String? status;
  final String? deposed;
  final Map<String, String> attributes;
  final List<String> dependencies;

  factory ResourceInstance.fromJson(Json j) => ResourceInstance(
        address: _s(j, 'address'),
        baseAddress: _s(j, 'base_address'),
        module: _s(j, 'module', 'root'),
        mode: _s(j, 'mode', 'managed'),
        type: _s(j, 'type'),
        name: _s(j, 'name'),
        index: _sn(j, 'index'),
        provider: _s(j, 'provider'),
        status: _sn(j, 'status'),
        deposed: _sn(j, 'deposed'),
        attributes: _ms(j, 'attributes'),
        dependencies: ((j['dependencies'] as List?) ?? const []).cast<String>(),
      );
}

// openapi: ModuleOut
class ModuleInfo {
  const ModuleInfo({required this.path, required this.resourceCount});
  final String path;
  final int resourceCount;
  factory ModuleInfo.fromJson(Json j) =>
      ModuleInfo(path: _s(j, 'path'), resourceCount: _i(j, 'resource_count'));
}

// openapi: StateInfoOut
class StateMeta {
  const StateMeta({
    required this.project,
    required this.workspace,
    required this.path,
    required this.versionId,
    required this.lastModified,
    required this.terraformVersion,
    required this.serial,
    required this.lineage,
    required this.resourceCount,
    required this.s3Bucket,
    required this.s3Key,
  });

  final String project;
  final String workspace;
  final String path;
  final String versionId;
  final String lastModified;
  final String terraformVersion;
  final int serial;
  final String lineage;
  final int resourceCount;
  final String s3Bucket;
  final String s3Key;

  factory StateMeta.fromJson(Json j) => StateMeta(
        project: _s(j, 'project'),
        workspace: _s(j, 'workspace'),
        path: _s(j, 'path', 'terraform.tfstate'),
        versionId: _s(j, 'version_id'),
        lastModified: _s(j, 'last_modified'),
        terraformVersion: _s(j, 'terraform_version'),
        serial: _i(j, 'serial'),
        lineage: _s(j, 'lineage'),
        resourceCount: _i(j, 'resource_count'),
        s3Bucket: _s(j, 's3_bucket'),
        s3Key: _s(j, 's3_key'),
      );
}

// openapi: StateDetail
class StateDetail {
  const StateDetail({
    required this.info,
    required this.outputs,
    required this.modules,
    required this.resources,
  });
  final StateMeta info;
  final List<StateOutput> outputs;
  final List<ModuleInfo> modules;
  final List<ResourceInstance> resources;

  factory StateDetail.fromJson(Json j) => StateDetail(
        info: StateMeta.fromJson(j['info'] as Json),
        outputs: _l(j, 'outputs', StateOutput.fromJson),
        modules: _l(j, 'modules', ModuleInfo.fromJson),
        resources: _l(j, 'resources', ResourceInstance.fromJson),
      );
}

// openapi: SearchHit
class SearchHit {
  const SearchHit({
    required this.project,
    required this.workspace,
    this.path = 'terraform.tfstate',
    required this.address,
    required this.type,
    required this.name,
    this.module = 'root',
    this.provider = '',
    this.mode = 'managed',
    this.index = '',
    this.attributes = const {},
  });
  final String project;
  final String workspace;
  final String path;
  final String address;

  StateRef get stateRef => (project: project, workspace: workspace, path: path);

  final String type;
  final String name;
  final String module;
  final String provider;
  final String mode;
  final String index;
  final Map<String, String> attributes;

  factory SearchHit.fromJson(Json j) => SearchHit(
        project: _s(j, 'project'),
        workspace: _s(j, 'workspace', 'default'),
        path: _s(j, 'path', 'terraform.tfstate'),
        address: _s(j, 'address'),
        type: _s(j, 'type'),
        name: _s(j, 'name'),
        module: _s(j, 'module', 'root'),
        provider: _s(j, 'provider'),
        mode: _s(j, 'mode', 'managed'),
        index: _s(j, 'index'),
        attributes: _ms(j, 'attributes'),
      );
}

// openapi: SearchResult
class SearchResult {
  const SearchResult({required this.items, this.cursor});
  final List<SearchHit> items;
  final String? cursor;
  factory SearchResult.fromJson(Json j) =>
      SearchResult(items: _l(j, 'items', SearchHit.fromJson), cursor: _sn(j, 'cursor'));
}

// openapi: DayActivity
class DayActivity {
  const DayActivity({required this.day, this.versions = 0, this.locks = 0});
  final String day;
  final int versions;
  final int locks;
  factory DayActivity.fromJson(Json j) =>
      DayActivity(day: _s(j, 'day'), versions: _i(j, 'versions'), locks: _i(j, 'locks'));
}

// openapi: Dashboard
class DashboardData {
  const DashboardData({
    required this.projects,
    required this.states,
    required this.resources,
    required this.versions,
    required this.locked,
    required this.lockAlerts,
    required this.lockThresholdMinutes,
    required this.byType,
    required this.byProvider,
    required this.byModule,
    required this.byProject,
    required this.terraformVersions,
    required this.providersInUse,
    required this.activity,
    required this.locks,
    required this.recent,
  });

  final int projects;
  final int states;
  final int resources;
  final int versions;
  final int locked;
  final int lockAlerts;
  final int lockThresholdMinutes;
  final Map<String, int> byType;
  final Map<String, int> byProvider;
  final Map<String, int> byModule;
  final Map<String, int> byProject;
  final Map<String, int> terraformVersions;
  final List<String> providersInUse;
  final List<DayActivity> activity;
  final List<ActiveLock> locks;
  final List<Project> recent;

  factory DashboardData.fromJson(Json j) => DashboardData(
        projects: _i(j, 'projects'),
        states: _i(j, 'states'),
        resources: _i(j, 'resources'),
        versions: _i(j, 'versions'),
        locked: _i(j, 'locked'),
        lockAlerts: _i(j, 'lock_alerts'),
        lockThresholdMinutes: _i(j, 'lock_threshold_minutes', 30),
        byType: _mi(j, 'by_type'),
        byProvider: _mi(j, 'by_provider'),
        byModule: _mi(j, 'by_module'),
        byProject: _mi(j, 'by_project'),
        terraformVersions: _mi(j, 'terraform_versions'),
        providersInUse: ((j['providers_in_use'] as List?) ?? const []).cast<String>(),
        activity: _l(j, 'activity', DayActivity.fromJson),
        locks: _l(j, 'locks', ActiveLock.fromJson),
        recent: _l(j, 'recent', Project.fromJson),
      );
}

// openapi: Facets
class Facets {
  const Facets({
    required this.resourceTypes,
    required this.terraformVersions,
    required this.providers,
    required this.projects,
  });
  final Map<String, int> resourceTypes;
  final Map<String, int> terraformVersions;
  final Map<String, int> providers;
  final List<String> projects;

  factory Facets.fromJson(Json j) => Facets(
        resourceTypes: _mi(j, 'resource_types'),
        terraformVersions: _mi(j, 'terraform_versions'),
        providers: _mi(j, 'providers'),
        projects: ((j['projects'] as List?) ?? const []).cast<String>(),
      );
}

// openapi: AttrChange
class AttrChange {
  const AttrChange({required this.key, required this.kind, this.oldValue, this.newValue});
  final String key;

  /// added | removed | changed
  final String kind;
  final String? oldValue;
  final String? newValue;
  factory AttrChange.fromJson(Json j) => AttrChange(
        key: _s(j, 'key'),
        kind: _s(j, 'kind'),
        oldValue: _sn(j, 'old'),
        newValue: _sn(j, 'new'),
      );
}

// openapi: ResourceChange
class ResourceChange {
  const ResourceChange({
    required this.address,
    required this.type,
    required this.name,
    required this.module,
    this.attributes = const {},
  });
  final String address;
  final String type;
  final String name;
  final String module;
  final Map<String, String> attributes;
  factory ResourceChange.fromJson(Json j) => ResourceChange(
        address: _s(j, 'address'),
        type: _s(j, 'type'),
        name: _s(j, 'name'),
        module: _s(j, 'module', 'root'),
        attributes: _ms(j, 'attributes'),
      );
}

// openapi: ResourceModified
class ResourceModified extends ResourceChange {
  const ResourceModified({
    required super.address,
    required super.type,
    required super.name,
    required super.module,
    this.changes = const [],
    this.sensitiveChanged = false,
    this.dependenciesChanged = false,
    this.unifiedDiff = '',
  });
  final List<AttrChange> changes;
  final bool sensitiveChanged;
  final bool dependenciesChanged;
  final String unifiedDiff;
  factory ResourceModified.fromJson(Json j) => ResourceModified(
        address: _s(j, 'address'),
        type: _s(j, 'type'),
        name: _s(j, 'name'),
        module: _s(j, 'module', 'root'),
        changes: _l(j, 'changes', AttrChange.fromJson),
        sensitiveChanged: _b(j, 'sensitive_changed'),
        dependenciesChanged: _b(j, 'dependencies_changed'),
        unifiedDiff: _s(j, 'unified_diff'),
      );
}

// openapi: OutputChange
class OutputChange {
  const OutputChange({required this.name, required this.kind, this.oldValue, this.newValue});
  final String name;
  final String kind;
  final String? oldValue;
  final String? newValue;
  factory OutputChange.fromJson(Json j) => OutputChange(
        name: _s(j, 'name'),
        kind: _s(j, 'kind'),
        oldValue: _sn(j, 'old'),
        newValue: _sn(j, 'new'),
      );
}

// openapi: StateInfo
class DiffSide {
  const DiffSide({
    this.versionId = '',
    this.lastModified = '',
    this.terraformVersion = '',
    this.serial = 0,
    this.resourceCount = 0,
  });
  final String versionId;
  final String lastModified;
  final String terraformVersion;
  final int serial;
  final int resourceCount;
  factory DiffSide.fromJson(Json j) => DiffSide(
        versionId: _s(j, 'version_id'),
        lastModified: _s(j, 'last_modified'),
        terraformVersion: _s(j, 'terraform_version'),
        serial: _i(j, 'serial'),
        resourceCount: _i(j, 'resource_count'),
      );
}

// openapi: DiffCounts
class DiffCounts {
  const DiffCounts({this.added = 0, this.removed = 0, this.modified = 0, this.unchanged = 0});
  final int added;
  final int removed;
  final int modified;
  final int unchanged;
  factory DiffCounts.fromJson(Json j) => DiffCounts(
        added: _i(j, 'added'),
        removed: _i(j, 'removed'),
        modified: _i(j, 'modified'),
        unchanged: _i(j, 'unchanged'),
      );
}

// openapi: StateDiff
class StateDiff {
  const StateDiff({
    required this.from,
    required this.to,
    required this.summary,
    required this.added,
    required this.removed,
    required this.modified,
    required this.outputs,
  });
  final DiffSide from;
  final DiffSide to;
  final DiffCounts summary;
  final List<ResourceChange> added;
  final List<ResourceChange> removed;
  final List<ResourceModified> modified;
  final List<OutputChange> outputs;

  factory StateDiff.fromJson(Json j) => StateDiff(
        from: DiffSide.fromJson(j['from'] as Json),
        to: DiffSide.fromJson(j['to'] as Json),
        summary: DiffCounts.fromJson(j['summary'] as Json),
        added: _l(j, 'added', ResourceChange.fromJson),
        removed: _l(j, 'removed', ResourceChange.fromJson),
        modified: _l(j, 'modified', ResourceModified.fromJson),
        outputs: _l(j, 'outputs', OutputChange.fromJson),
      );
}

// openapi: DiffSummaryOut
class DiffSummary {
  const DiffSummary({required this.summary, required this.modelId});
  final String summary;
  final String modelId;
  factory DiffSummary.fromJson(Json j) =>
      DiffSummary(summary: _s(j, 'summary'), modelId: _s(j, 'model_id'));
}

// openapi: GraphNode
class GraphNode {
  const GraphNode({
    required this.id,
    required this.kind,
    this.type = '',
    this.name = '',
    this.module = 'root',
    this.provider = '',
    this.instances = 1,
  });
  final String id;

  /// resource | data | module
  final String kind;
  final String type;
  final String name;
  final String module;
  final String provider;
  final int instances;
  factory GraphNode.fromJson(Json j) => GraphNode(
        id: _s(j, 'id'),
        kind: _s(j, 'kind', 'resource'),
        type: _s(j, 'type'),
        name: _s(j, 'name'),
        module: _s(j, 'module', 'root'),
        provider: _s(j, 'provider'),
        instances: _i(j, 'instances', 1),
      );
}

// openapi: GraphEdge
class GraphEdge {
  const GraphEdge({required this.source, required this.target});
  final String source;
  final String target;
  factory GraphEdge.fromJson(Json j) => GraphEdge(source: _s(j, 'source'), target: _s(j, 'target'));
}

// openapi: ModuleEdge
class ModuleEdge {
  const ModuleEdge({required this.source, required this.target, required this.count});
  final String source;
  final String target;
  final int count;
  factory ModuleEdge.fromJson(Json j) =>
      ModuleEdge(source: _s(j, 'source'), target: _s(j, 'target'), count: _i(j, 'count'));
}

// openapi: Graph
class DependencyGraph {
  const DependencyGraph({required this.nodes, required this.edges, required this.moduleEdges});
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<ModuleEdge> moduleEdges;
  factory DependencyGraph.fromJson(Json j) => DependencyGraph(
        nodes: _l(j, 'nodes', GraphNode.fromJson),
        edges: _l(j, 'edges', GraphEdge.fromJson),
        moduleEdges: _l(j, 'module_edges', ModuleEdge.fromJson),
      );
}

// ---- Recursos AWS (mapa Terraform -> AWS) ------------------------------------------------
// openapi: AwsMapStatus
class AwsMapStatus {
  const AwsMapStatus({
    required this.state,
    required this.stale,
    required this.staleAfterDays,
    required this.entries,
    this.reviewedAt,
    this.issues = const [],
  });
  final String state; // ok | degraded | unavailable
  final bool stale;
  final String? reviewedAt;
  final int staleAfterDays;
  final int entries;
  final List<String> issues;

  bool get unavailable => state == 'unavailable';
  bool get needsAttention => state != 'ok' || stale;

  factory AwsMapStatus.fromJson(Json j) => AwsMapStatus(
        state: _s(j, 'state', 'unavailable'),
        stale: _b(j, 'stale'),
        reviewedAt: _sn(j, 'reviewed_at'),
        staleAfterDays: _i(j, 'stale_after_days'),
        entries: _i(j, 'entries'),
        issues: ((j['issues'] as List?) ?? const []).cast<String>(),
      );
}

// openapi: AwsComponent
class AwsComponent {
  const AwsComponent({required this.address, required this.tfType, this.cfnType});
  final String address;
  final String tfType;
  final String? cfnType;

  factory AwsComponent.fromJson(Json j) =>
      AwsComponent(address: _s(j, 'address'), tfType: _s(j, 'tf_type'), cfnType: _sn(j, 'cfn_type'));
}

// openapi: AwsResourceOut
class AwsResource {
  const AwsResource({
    required this.cfnType,
    required this.identity,
    required this.name,
    required this.status,
    required this.primaries,
    required this.components,
  });
  final String cfnType;
  final String identity;
  final String name;
  final String status; // verified | provisional
  final List<AwsComponent> primaries;
  final List<AwsComponent> components;

  bool get provisional => status != 'verified';
  List<AwsComponent> get all => [...primaries, ...components];

  factory AwsResource.fromJson(Json j) => AwsResource(
        cfnType: _s(j, 'cfn_type'),
        identity: _s(j, 'identity'),
        name: _s(j, 'name'),
        status: _s(j, 'status', 'provisional'),
        primaries: _l(j, 'primaries', AwsComponent.fromJson),
        components: _l(j, 'components', AwsComponent.fromJson),
      );
}

// openapi: UnmappedOut
class UnmappedResource {
  const UnmappedResource({
    required this.address,
    required this.tfType,
    required this.reason,
    this.module = 'root',
    this.detail = '',
  });
  final String address;
  final String tfType;
  final String module;
  final String reason;
  final String detail;

  factory UnmappedResource.fromJson(Json j) => UnmappedResource(
        address: _s(j, 'address'),
        tfType: _s(j, 'tf_type'),
        module: _s(j, 'module', 'root'),
        reason: _s(j, 'reason'),
        detail: _s(j, 'detail'),
      );
}

// openapi: AwsCoverage
class AwsCoverage {
  const AwsCoverage({
    required this.managedTotal,
    required this.mapped,
    required this.unmapped,
    required this.percent,
    required this.awsResources,
    required this.unmappedByReason,
  });
  final int managedTotal;
  final int mapped;
  final int unmapped;
  final double percent;
  final int awsResources;
  final Map<String, int> unmappedByReason;

  factory AwsCoverage.fromJson(Json j) => AwsCoverage(
        managedTotal: _i(j, 'managed_total'),
        mapped: _i(j, 'mapped'),
        unmapped: _i(j, 'unmapped'),
        percent: ((j['percent'] as num?) ?? 0).toDouble(),
        awsResources: _i(j, 'aws_resources'),
        unmappedByReason: _mi(j, 'unmapped_by_reason'),
      );
}

// openapi: AwsResources
class AwsResources {
  const AwsResources({
    required this.map,
    required this.coverage,
    required this.resources,
    required this.unmapped,
    required this.helpers,
    required this.data,
  });
  final AwsMapStatus map;
  final AwsCoverage coverage;
  final List<AwsResource> resources;
  final List<UnmappedResource> unmapped;
  final List<AwsComponent> helpers;
  final List<AwsComponent> data;

  factory AwsResources.fromJson(Json j) => AwsResources(
        map: AwsMapStatus.fromJson(j['map'] as Json),
        coverage: AwsCoverage.fromJson(j['coverage'] as Json),
        resources: _l(j, 'resources', AwsResource.fromJson),
        unmapped: _l(j, 'unmapped', UnmappedResource.fromJson),
        helpers: _l(j, 'helpers', AwsComponent.fromJson),
        data: _l(j, 'data', AwsComponent.fromJson),
      );
}
