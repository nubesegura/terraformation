import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'layout.dart';

const int kMaxGraphNodes = 600;

class GraphTab extends ConsumerWidget {
  const GraphTab({super.key, required this.stateRef, required this.version});
  final StateRef stateRef;
  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (stateRef, version);
    return AsyncView<DependencyGraph>(
      value: ref.watch(graphProvider(key)),
      onRetry: () => ref.invalidate(graphProvider(key)),
      builder: (g) => DependencyGraphView(graph: g),
    );
  }
}

/// Grafo interactivo (zoom/pan, selección, filtros por módulo y texto).
class DependencyGraphView extends StatefulWidget {
  const DependencyGraphView({super.key, required this.graph});
  final DependencyGraph graph;

  @override
  State<DependencyGraphView> createState() => _DependencyGraphViewState();
}

class _DependencyGraphViewState extends State<DependencyGraphView> {
  bool moduleMode = false;
  String? moduleFilter;
  String query = '';
  String? selected;
  final _tc = TransformationController();
  GraphLayout? _layout;
  List<GraphNode> _nodes = const [];
  List<GraphEdge> _edges = const [];
  String? _key;
  String? _fitKey;

  List<String> get _modules =>
      (widget.graph.nodes.map((n) => n.module).toSet().toList()..sort());

  void _compute() {
    var nodes = widget.graph.nodes;
    var edges = widget.graph.edges;
    if (moduleMode) {
      (nodes, edges) = moduleGraph(widget.graph);
    } else if (moduleFilter != null) {
      final keep = nodes.where((n) => n.module == moduleFilter).map((n) => n.id).toSet();
      final withNeighbors = {
        ...keep,
        for (final e in edges)
          if (keep.contains(e.source) || keep.contains(e.target)) ...[e.source, e.target],
      };
      nodes = nodes.where((n) => withNeighbors.contains(n.id)).toList();
      edges = edges.where((e) => withNeighbors.contains(e.source) && withNeighbors.contains(e.target)).toList();
    }
    if (nodes.length > kMaxGraphNodes) {
      nodes = nodes.take(kMaxGraphNodes).toList();
      final ids = nodes.map((n) => n.id).toSet();
      edges = edges.where((e) => ids.contains(e.source) && ids.contains(e.target)).toList();
    }
    _nodes = nodes;
    _edges = edges;
    _layout = layoutGraph(nodes, edges, iterations: nodes.length > 250 ? 70 : 120);
    _key = '$moduleMode|$moduleFilter';
    selected = null;
    _fitKey = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.graph.nodes.isEmpty) {
      return const Center(child: Text('Este state no tiene recursos.'));
    }
    if (_layout == null || _key != '$moduleMode|$moduleFilter') _compute();
    final layout = _layout!;
    final moduleList = {for (final (i, m) in _modules.indexed) m: i};
    Color colorOf(GraphNode n) => Palette.of(moduleList[moduleMode ? n.id : n.module] ?? 0);

    final adjacency = <String, Set<String>>{};
    for (final e in _edges) {
      adjacency.putIfAbsent(e.source, () => {}).add(e.target);
      adjacency.putIfAbsent(e.target, () => {}).add(e.source);
    }
    final sel = selected == null ? null : _nodes.where((n) => n.id == selected).firstOrNull;
    final dependsOn = sel == null ? <String>[] : [for (final e in _edges) if (e.source == sel.id) e.target];
    final usedBy = sel == null ? <String>[] : [for (final e in _edges) if (e.target == sel.id) e.source];

    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Recursos'), icon: Icon(Icons.hub_outlined)),
              ButtonSegment(value: true, label: Text('Módulos'), icon: Icon(Icons.account_tree_outlined)),
            ],
            selected: {moduleMode},
            onSelectionChanged: (s) => setState(() => moduleMode = s.first),
          ),
          if (!moduleMode)
            DropdownButton<String?>(
              value: moduleFilter,
              hint: const Text('Todos los módulos'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos los módulos')),
                for (final m in _modules) DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) => setState(() => moduleFilter = v),
            ),
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Resaltar…', isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => setState(() => query = v.toLowerCase()),
            ),
          ),
          Text('${_nodes.length} nodos · ${_edges.length} dependencias', style: Theme.of(context).textTheme.bodySmall),
          if (widget.graph.nodes.length > kMaxGraphNodes && !moduleMode)
            const Tag('mostrando los primeros 600; filtra por módulo', color: Palette.modified),
        ]),
      ),
      Expanded(
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Row(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                if (_fitKey != _key) {
                  _fitKey = _key;
                  final scale = math.min(math.min(c.maxWidth / layout.size.width, c.maxHeight / layout.size.height), 1.4);
                  final dx = (c.maxWidth - layout.size.width * scale) / 2;
                  final dy = (c.maxHeight - layout.size.height * scale) / 2;
                  _tc.value = Matrix4.identity()
                    ..translateByDouble(dx, dy, 0, 1)
                    ..scaleByDouble(scale, scale, 1, 1);
                }
                return GestureDetector(
                  onTapUp: (d) {
                    final p = _tc.toScene(d.localPosition);
                    String? hit;
                    var best = 18.0;
                    for (final n in _nodes) {
                      final o = layout.positions[n.id]!;
                      final dist = (o - p).distance;
                      if (dist < best) {
                        best = dist;
                        hit = n.id;
                      }
                    }
                    setState(() => selected = hit);
                  },
                  child: InteractiveViewer(
                    transformationController: _tc,
                    constrained: false,
                    minScale: 0.15,
                    maxScale: 4,
                    boundaryMargin: const EdgeInsets.all(400),
                    child: SizedBox(
                      width: layout.size.width,
                      height: layout.size.height,
                      child: CustomPaint(
                        painter: _GraphPainter(
                          nodes: _nodes,
                          edges: _edges,
                          layout: layout,
                          colorOf: colorOf,
                          selected: selected,
                          neighbors: selected == null ? const {} : (adjacency[selected] ?? const {}),
                          query: query,
                          labelAll: _nodes.length <= 60,
                          textColor: Theme.of(context).colorScheme.onSurface,
                          edgeColor: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (sel != null)
              SizedBox(
                width: 280,
                child: _NodePanel(node: sel, dependsOn: dependsOn, usedBy: usedBy, onSelect: (id) => setState(() => selected = id)),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 10, children: [
        for (final m in _modules.take(8))
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: Palette.of(moduleList[m]!), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(m, style: const TextStyle(fontSize: 11)),
          ]),
      ]),
    ]);
  }
}

class _NodePanel extends StatelessWidget {
  const _NodePanel({required this.node, required this.dependsOn, required this.usedBy, required this.onSelect});
  final GraphNode node;
  final List<String> dependsOn;
  final List<String> usedBy;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget list(String title, List<String> ids) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 12),
          Text('$title (${ids.length})', style: t.labelLarge),
          for (final id in ids.take(30))
            InkWell(onTap: () => onSelect(id), child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(id, style: const TextStyle(fontSize: 11)))),
        ]);
    return Container(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(node.id, style: t.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            Tag(node.kind),
            if (node.type.isNotEmpty) Tag(node.type),
            Tag(node.module),
            if (node.instances > 1) Tag('${node.instances} instancias'),
          ]),
          list('Depende de', dependsOn),
          list('Usado por', usedBy),
        ]),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.layout,
    required this.colorOf,
    required this.selected,
    required this.neighbors,
    required this.query,
    required this.labelAll,
    required this.textColor,
    required this.edgeColor,
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final GraphLayout layout;
  final Color Function(GraphNode) colorOf;
  final String? selected;
  final Set<String> neighbors;
  final String query;
  final bool labelAll;
  final Color textColor;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final hasSel = selected != null;
    for (final e in edges) {
      final a = layout.positions[e.source];
      final b = layout.positions[e.target];
      if (a == null || b == null) continue;
      final active = hasSel && (e.source == selected || e.target == selected);
      final paint = Paint()
        ..color = active ? textColor.withValues(alpha: 0.85) : edgeColor.withValues(alpha: hasSel ? 0.12 : 0.35)
        ..strokeWidth = active ? 1.8 : 1;
      canvas.drawLine(a, b, paint);
      // flecha hacia el destino (la dependencia)
      final dir = (b - a);
      final len = dir.distance;
      if (len > 24) {
        final u = dir / len;
        final tip = b - u * 11;
        final left = Offset(-u.dy, u.dx) * 3.5;
        canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - u.dx * 7 + left.dx, tip.dy - u.dy * 7 + left.dy)
            ..lineTo(tip.dx - u.dx * 7 - left.dx, tip.dy - u.dy * 7 - left.dy)
            ..close(),
          paint..style = PaintingStyle.fill,
        );
      }
    }
    for (final n in nodes) {
      final o = layout.positions[n.id]!;
      final dim = (hasSel && n.id != selected && !neighbors.contains(n.id)) ||
          (query.isNotEmpty && !n.id.toLowerCase().contains(query));
      final r = math.min(14.0, 6.0 + math.sqrt(n.instances.toDouble()) * 2) + (n.kind == 'module' ? 3 : 0);
      final c = colorOf(n);
      final fill = Paint()..color = c.withValues(alpha: dim ? 0.18 : 0.95);
      if (n.kind == 'data') {
        canvas.drawRect(Rect.fromCenter(center: o, width: r * 1.7, height: r * 1.7), fill);
      } else {
        canvas.drawCircle(o, r, fill);
      }
      if (n.id == selected) {
        canvas.drawCircle(
            o, r + 4, Paint()..color = textColor..style = PaintingStyle.stroke..strokeWidth = 2);
      }
      final showLabel = !dim && (labelAll || n.id == selected || neighbors.contains(n.id) || (query.isNotEmpty));
      if (showLabel) {
        final label = n.kind == 'module' ? n.id : (n.type.isEmpty ? n.id : '${n.type}.${n.name}');
        final tp = TextPainter(
          text: TextSpan(text: label, style: TextStyle(fontSize: 10.5, color: textColor)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 170);
        tp.paint(canvas, o + Offset(-tp.width / 2, r + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.selected != selected || old.query != query || old.nodes != nodes || old.layout != layout;
}
