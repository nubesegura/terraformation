import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../dashboard/dashboard_page.dart' show BarList;
import '../aws/aws_resources_tab.dart';
import '../graph/graph_view.dart';
import '../state/state_tab.dart';
import 'locks_tab.dart';
import 'timeline_tab.dart';

const projectTabs = ['aws', 'overview', 'timeline', 'state', 'graph', 'locks'];

class ProjectPage extends ConsumerWidget {
  const ProjectPage({super.key, required this.stateRef, this.tab, this.version});
  final StateRef stateRef;
  final String? tab;
  final String? version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = stateRef;
    final p = ref.watch(projectProvider(key));
    return AsyncView<Project>(
      value: p,
      onRetry: () => ref.invalidate(projectProvider(key)),
      builder: (proj) => _Body(proj: proj, tab: tab, version: version),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.proj, this.tab, this.version});
  final Project proj;
  final String? tab;
  final String? version;

  @override
  Widget build(BuildContext context) {
    final idx = projectTabs.indexOf(tab ?? 'aws').clamp(0, projectTabs.length - 1);
    final t = Theme.of(context).textTheme;
    final ver = version ?? proj.currentVersionId ?? 'current';
    final ref = (project: proj.project, workspace: proj.workspace, path: proj.path);
    return DefaultTabController(
      key: ValueKey('${proj.label}-$idx'),
      length: projectTabs.length,
      initialIndex: idx,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/projects'), icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(proj.project, style: t.headlineSmall),
                if (proj.workspace != 'default') Tag(proj.workspace, icon: Icons.layers_outlined),
                if (proj.statePath.isNotEmpty) Tag(proj.statePath, icon: Icons.account_tree_outlined),
                LockBadge(lock: proj.lock),
                Tag('Terraform ${proj.terraformVersion ?? '—'}', icon: Icons.terminal),
                Tag('serial ${proj.serial ?? '—'}'),
                Tag('${proj.resourceCount} recursos'),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Recursos AWS', icon: Icon(Icons.cloud_outlined)),
            Tab(text: 'Resumen', icon: Icon(Icons.dashboard_outlined)),
            Tab(text: 'Línea de tiempo', icon: Icon(Icons.timeline)),
            Tab(text: 'Terraform', icon: Icon(Icons.dns_outlined)),
            Tab(text: 'Grafo', icon: Icon(Icons.hub_outlined)),
            Tab(text: 'Locks', icon: Icon(Icons.lock_clock)),
          ]),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                AwsResourcesTab(stateRef: ref),
                _Overview(proj: proj),
                TimelineTab(stateRef: ref),
                StateTab(stateRef: ref, initialVersion: ver),
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  child: GraphTab(stateRef: ref, version: ver),
                ),
                LocksTab(stateRef: ref),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.proj});
  final Project proj;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 230, child: StatCard(label: 'Recursos', value: '${proj.resourceCount}', icon: Icons.dns_outlined)),
          SizedBox(width: 230, child: StatCard(label: 'Versiones', value: '${proj.versionCount}', icon: Icons.history, color: Palette.of(4))),
          SizedBox(
            width: 230,
            child: StatCard(
                label: 'Última modificación',
                value: relativeTime(proj.lastModified),
                icon: Icons.schedule,
                color: Palette.of(1)),
          ),
          SizedBox(
            width: 230,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Actividad 14 días'),
                  const SizedBox(height: 8),
                  Sparkline(values: proj.activity, width: 190, height: 36),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final children = [
            SectionCard(title: 'Recursos por tipo', child: BarList(proj.byType)),
            SectionCard(title: 'Recursos por provider', child: BarList(proj.byProvider)),
            SectionCard(title: 'Recursos por módulo', child: BarList(proj.byModule)),
          ];
          if (c.maxWidth < 900) {
            return Column(children: [for (final w in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: w)]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in children) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: w)),
          ]);
        }),
        if (proj.lineage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(alignment: Alignment.centerLeft, child: SelectableText('lineage: ${proj.lineage}', style: Theme.of(context).textTheme.bodySmall)),
          ),
      ]),
    );
  }
}
