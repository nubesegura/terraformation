import 'package:flutter_test/flutter_test.dart';
import 'package:terraformation_web/core/api/models.dart';
import 'package:terraformation_web/core/state_ref.dart';
import 'package:terraformation_web/features/graph/layout.dart';
import 'package:terraformation_web/shared/format.dart';

void main() {
  test('Project parsea lock y valores por defecto', () {
    final p = Project.fromJson({
      'project': 'a',
      'workspace': 'dev',
      'resource_count': 3,
      'lock': {'status': 'locked', 'who': 'ana', 'alert': true, 'duration_s': 4000},
      'activity': [0, 1, 2],
      'by_type': {'aws_s3_bucket': 2},
    });
    expect(p.label, 'a:dev');
    expect(p.lock.isLocked && p.lock.alert, isTrue);
    expect(p.byType['aws_s3_bucket'], 2);
    final none = Project.fromJson({'project': 'b', 'workspace': 'default', 'lock': {'status': 'none_detected'}});
    expect(none.lock.noneDetected, isTrue);
  });

  test('Project con ruta anidada genera etiqueta y URL del state', () {
    final p = Project.fromJson({
      'project': 'a',
      'workspace': 'dev',
      'path': 'network/prod.tfstate',
      'lock': {'status': 'none_detected'},
    });
    expect(p.label, 'a:dev/network/prod.tfstate');
    expect(stateLabel(p.stateRef), p.label);
    expect(stateLocation(p.stateRef, sub: 'diff', extra: {'from': 'v1'}),
        '/projects/a/diff?workspace=dev&path=network%2Fprod.tfstate&from=v1');
    final root = Project.fromJson({'project': 'b', 'lock': {'status': 'none_detected'}});
    expect(root.path, defaultStatePath);
    expect(stateLocation(root.stateRef), '/projects/b?workspace=default');
  });

  test('AwsResources parsea grupos, sin mapear y estado del mapa', () {
    final r = AwsResources.fromJson({
      'map': {'state': 'degraded', 'stale': true, 'stale_after_days': 180, 'entries': 157, 'issues': ['x']},
      'coverage': {
        'managed_total': 5,
        'mapped': 4,
        'unmapped': 1,
        'percent': 80,
        'aws_resources': 3,
        'unmapped_by_reason': {'orphan_child': 1},
      },
      'resources': [
        {
          'cfn_type': 'AWS::S3::Bucket',
          'identity': 'b',
          'name': 'b',
          'status': 'provisional',
          'primaries': [
            {'address': 'aws_s3_bucket.b', 'tf_type': 'aws_s3_bucket', 'cfn_type': 'AWS::S3::Bucket'},
          ],
          'components': [
            {'address': 'aws_s3_bucket_policy.b', 'tf_type': 'aws_s3_bucket_policy'},
          ],
        },
      ],
      'unmapped': [
        {'address': 'aws_iam_access_key.k', 'tf_type': 'aws_iam_access_key', 'reason': 'orphan_child'},
      ],
      'helpers': [],
      'data': [],
    });
    expect(r.map.needsAttention && !r.map.unavailable, isTrue);
    expect(r.coverage.percent, 80.0);
    expect(r.resources.single.provisional, isTrue);
    expect(r.resources.single.all.length, 2);
    expect(r.unmapped.single.module, 'root');
    expect(AwsMapStatus.fromJson({'state': 'unavailable', 'stale': false, 'stale_after_days': 1, 'entries': 0}).unavailable, isTrue);
  });

  test('StateDiff parsea alias from/to y cambios', () {
    final d = StateDiff.fromJson({
      'from': {'version_id': 'v1', 'serial': 1},
      'to': {'version_id': 'v2', 'serial': 2},
      'summary': {'added': 1, 'removed': 0, 'modified': 1, 'unchanged': 3},
      'added': [
        {'address': 'a.b', 'type': 'a', 'name': 'b', 'module': 'root', 'attributes': {'x': '1'}},
      ],
      'removed': [],
      'modified': [
        {
          'address': 'c.d',
          'type': 'c',
          'name': 'd',
          'module': 'root',
          'changes': [
            {'key': 'tags.team', 'kind': 'changed', 'old': 'a', 'new': 'b'},
          ],
          'sensitive_changed': true,
          'unified_diff': '--- a\n+++ b\n',
        },
      ],
      'outputs': [],
    });
    expect(d.from.versionId, 'v1');
    expect(d.summary.modified, 1);
    expect(d.modified.single.changes.single.newValue, 'b');
    expect(d.modified.single.sensitiveChanged, isTrue);
  });

  test('layout del grafo es determinista y agrupa en el área', () {
    final nodes = [
      for (var i = 0; i < 12; i++) GraphNode(id: 'n$i', kind: 'resource', module: i < 6 ? 'root' : 'module.a'),
    ];
    final edges = [for (var i = 1; i < 12; i++) GraphEdge(source: 'n$i', target: 'n${i - 1}')];
    final a = layoutGraph(nodes, edges);
    final b = layoutGraph(nodes, edges);
    expect(a.positions['n3'], b.positions['n3']);
    for (final o in a.positions.values) {
      expect(o.dx, inInclusiveRange(0, a.size.width));
      expect(o.dy, inInclusiveRange(0, a.size.height));
    }
    final linked = (a.positions['n1']! - a.positions['n0']!).distance;
    final far = (a.positions['n1']! - a.positions['n11']!).distance;
    expect(linked, lessThan(far));
  });

  test('moduleGraph agrega nodos y aristas por módulo', () {
    final g = DependencyGraph(
      nodes: const [
        GraphNode(id: 'a.x', kind: 'resource', module: 'root'),
        GraphNode(id: 'module.m.b.y', kind: 'resource', module: 'module.m'),
      ],
      edges: const [GraphEdge(source: 'a.x', target: 'module.m.b.y')],
      moduleEdges: const [ModuleEdge(source: 'root', target: 'module.m', count: 1)],
    );
    final (nodes, edges) = moduleGraph(g);
    expect(nodes.map((n) => n.id), ['module.m', 'root']);
    expect(edges.single.target, 'module.m');
  });

  test('formatos de tiempo', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    expect(relativeTime('2026-01-01T11:55:00Z', now: now), 'hace 5 min');
    expect(relativeTime('2025-12-30T12:00:00Z', now: now), 'hace 2 d');
    expect(formatDuration(3700), '1 h 1 min');
    expect(formatDuration(null), '—');
  });
}
