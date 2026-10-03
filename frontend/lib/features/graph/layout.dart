import 'dart:math' as math;
import 'dart:ui';

import '../../core/api/models.dart';

/// Posiciones calculadas (coordenadas de escena) para cada nodo.
class GraphLayout {
  GraphLayout(this.positions, this.size);
  final Map<String, Offset> positions;
  final Size size;
}

/// Layout dirigido por fuerzas (Fruchterman–Reingold) determinista.
///
/// Los nodos arrancan agrupados por módulo, de modo que los módulos tiendan a
/// verse como cúmulos.
GraphLayout layoutGraph(
  List<GraphNode> nodes,
  List<GraphEdge> edges, {
  int iterations = 120,
  int seed = 7,
}) {
  final n = nodes.length;
  if (n == 0) return GraphLayout({}, const Size(400, 300));
  final side = math.max(300.0, math.sqrt(n) * 110);
  final rng = math.Random(seed);
  final modules = nodes.map((e) => e.module).toSet().toList()..sort();
  final centers = <String, Offset>{
    for (var i = 0; i < modules.length; i++)
      modules[i]: Offset(
        side / 2 + math.cos(2 * math.pi * i / modules.length) * side * 0.32,
        side / 2 + math.sin(2 * math.pi * i / modules.length) * side * 0.32,
      ),
  };
  final index = {for (var i = 0; i < n; i++) nodes[i].id: i};
  final pos = List<Offset>.generate(n, (i) {
    final c = centers[nodes[i].module]!;
    return c + Offset((rng.nextDouble() - 0.5) * side * 0.25, (rng.nextDouble() - 0.5) * side * 0.25);
  });
  final links = [
    for (final e in edges)
      if (index.containsKey(e.source) && index.containsKey(e.target)) (index[e.source]!, index[e.target]!),
  ];

  final area = side * side;
  final k = math.sqrt(area / n) * 0.8;
  var temp = side / 8;
  final cool = temp / (iterations + 1);
  final disp = List<Offset>.filled(n, Offset.zero);

  for (var it = 0; it < iterations; it++) {
    for (var i = 0; i < n; i++) {
      disp[i] = Offset.zero;
    }
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var d = pos[i] - pos[j];
        var dist = d.distance;
        if (dist < 0.01) {
          d = Offset(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5);
          dist = d.distance + 0.01;
        }
        final f = (k * k) / dist;
        final push = d / dist * f;
        disp[i] += push;
        disp[j] -= push;
      }
    }
    for (final (a, b) in links) {
      final d = pos[a] - pos[b];
      final dist = math.max(d.distance, 0.01);
      final f = (dist * dist) / k;
      final pull = d / dist * f;
      disp[a] -= pull;
      disp[b] += pull;
    }
    for (var i = 0; i < n; i++) {
      // Débil atracción hacia el centro del módulo para conservar los cúmulos.
      final c = centers[nodes[i].module]!;
      disp[i] += (c - pos[i]) * 0.05;
      final len = math.max(disp[i].distance, 0.01);
      final step = math.min(len, temp);
      pos[i] = pos[i] + disp[i] / len * step;
      pos[i] = Offset(pos[i].dx.clamp(20.0, side - 20), pos[i].dy.clamp(20.0, side - 20));
    }
    temp -= cool;
  }
  // Recorta al cuadro delimitador (con margen para etiquetas) para que el grafo ocupe la escena.
  var minX = pos.first.dx, maxX = pos.first.dx, minY = pos.first.dy, maxY = pos.first.dy;
  for (final o in pos) {
    minX = math.min(minX, o.dx);
    maxX = math.max(maxX, o.dx);
    minY = math.min(minY, o.dy);
    maxY = math.max(maxY, o.dy);
  }
  const pad = 90.0;
  final shift = Offset(pad - minX, pad - minY);
  return GraphLayout(
    {for (var i = 0; i < n; i++) nodes[i].id: pos[i] + shift},
    Size(maxX - minX + pad * 2, maxY - minY + pad * 2),
  );
}

/// Grafo de módulos: un nodo por módulo y aristas agregadas.
(List<GraphNode>, List<GraphEdge>) moduleGraph(DependencyGraph g) {
  final mods = <String>{};
  for (final n in g.nodes) {
    mods.add(n.kind == 'module' ? n.id : n.module);
  }
  for (final e in g.moduleEdges) {
    mods..add(e.source)..add(e.target);
  }
  final nodes = [
    for (final m in (mods.toList()..sort()))
      GraphNode(
        id: m,
        kind: 'module',
        name: m,
        module: m,
        instances: g.nodes.where((n) => n.module == m && n.kind != 'module').length,
      ),
  ];
  final edges = [for (final e in g.moduleEdges) GraphEdge(source: e.source, target: e.target)];
  return (nodes, edges);
}
