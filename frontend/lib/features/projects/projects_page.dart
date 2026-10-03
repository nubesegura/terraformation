import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Proyectos', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Cada proyecto agrupa los states (*.tfstate) que contiene, ordenados por última modificación', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Filtrar por proyecto, workspace o ruta del state',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (v) => ref.read(projectsQueryProvider.notifier).set(v.trim()),
          ),
          const SizedBox(height: 16),
          AsyncView<ProjectList>(
            value: projects,
            onRetry: () => ref.invalidate(projectsProvider),
            builder: (list) => list.items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No hay proyectos todavía. Ejecuta el backfill o espera eventos de S3.'),
                  )
                : Column(children: [
                    for (final g in _groupByProject(list.items))
                      g.length == 1 ? _ProjectTile(p: g.single) : _ProjectGroup(states: g),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Agrupa los states por proyecto conservando el orden (más reciente primero).
List<List<Project>> _groupByProject(List<Project> items) {
  final groups = <String, List<Project>>{};
  for (final p in items) {
    groups.putIfAbsent(p.project, () => []).add(p);
  }
  return groups.values.toList();
}

class _ProjectGroup extends StatelessWidget {
  const _ProjectGroup({required this.states});
  final List<Project> states;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final resources = states.fold<int>(0, (a, p) => a + p.resourceCount);
    final locked = states.where((p) => p.lock.isLocked).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(Icons.folder_copy_outlined),
          title: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(states.first.project, style: t.titleMedium),
            Tag('${states.length} states', icon: Icons.account_tree_outlined),
            if (locked > 0) Tag('$locked bloqueado${locked > 1 ? 's' : ''}', color: Palette.locked),
          ]),
          subtitle: Text(
              'Modificado ${relativeTime(states.first.lastModified)} · $resources recursos en total',
              style: t.bodySmall),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          children: [for (final p in states) _ProjectTile(p: p, inGroup: true)],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.p, this.inGroup = false});
  final Project p;
  final bool inGroup;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go(stateLocation(p.stateRef)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(inGroup ? (p.statePath.isEmpty ? p.path : p.statePath) : p.project, style: t.titleMedium),
                    if (!inGroup && p.statePath.isNotEmpty) Tag(p.statePath, icon: Icons.account_tree_outlined),
                    if (p.workspace != 'default') Tag(p.workspace, icon: Icons.layers_outlined),
                    if (p.deleted) const Tag('state eliminado'),
                    LockBadge(lock: p.lock, dense: true),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    Text('Modificado ${relativeTime(p.lastModified)}', style: t.bodySmall),
                    Text('Serial ${p.serial ?? '—'}', style: t.bodySmall),
                    Text('Terraform ${p.terraformVersion ?? '—'}', style: t.bodySmall),
                    Text('${p.resourceCount} recursos', style: t.bodySmall),
                    Text('${p.versionCount} versiones', style: t.bodySmall),
                  ]),
                  if (p.lock.isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '🔒 ${p.lock.who} · ${p.lock.operation.replaceFirst('OperationType', '')} · desde ${relativeTime(p.lock.since)}',
                        style: t.bodySmall,
                      ),
                    ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Sparkline(values: p.activity),
                Text('14 días', style: t.labelSmall),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
