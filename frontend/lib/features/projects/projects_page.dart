import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../l10n/app_strings.dart';

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final projects = ref.watch(projectsProvider);
    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.navProjects, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(s.projectsSubtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: s.filterProjectsHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (v) => ref.read(projectsQueryProvider.notifier).set(v.trim()),
          ),
          const SizedBox(height: 16),
          AsyncView<ProjectList>(
            value: projects,
            onRetry: () => ref.invalidate(projectsProvider),
            builder: (list) => list.items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(s.noProjectsYet),
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

/// Groups the states by project keeping the order (most recent first).
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
    final s = context.s;
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
            Tag(s.statesCount(states.length), icon: Icons.account_tree_outlined),
            if (locked > 0) Tag(s.lockedCount(locked), color: Palette.locked),
          ]),
          subtitle: Text(
              s.groupSubtitle(relativeTime(s, states.first.lastModified), resources),
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
    final s = context.s;
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
                    if (p.deleted) Tag(s.stateDeleted),
                    LockBadge(lock: p.lock, dense: true),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    Text(s.modifiedAgo(relativeTime(s, p.lastModified)), style: t.bodySmall),
                    Text('Serial ${p.serial ?? '—'}', style: t.bodySmall),
                    Text(s.terraformVersion(p.terraformVersion ?? '—'), style: t.bodySmall),
                    Text(s.resourcesCount(p.resourceCount), style: t.bodySmall),
                    Text(s.versionsCount(p.versionCount), style: t.bodySmall),
                  ]),
                  if (p.lock.isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '🔒 ${s.whoSince(p.lock.who, p.lock.operation.replaceFirst('OperationType', ''), relativeTime(s, p.lock.since))}',
                        style: t.bodySmall,
                      ),
                    ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Sparkline(values: p.activity),
                Text(s.days14, style: t.labelSmall),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
