import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../l10n/app_strings.dart';

/// Translated reason why a resource could not be associated with an AWS resource.
String reasonLabel(BuildContext context, String reason) => context.s.unmappedReason(reason);

/// Main view: the AWS resources the state deploys, grouped by CloudFormation type.
class AwsResourcesTab extends ConsumerStatefulWidget {
  const AwsResourcesTab({super.key, required this.stateRef});
  final StateRef stateRef;

  @override
  ConsumerState<AwsResourcesTab> createState() => _AwsResourcesTabState();
}

class _AwsResourcesTabState extends ConsumerState<AwsResourcesTab> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final key = widget.stateRef;
    return AsyncView<AwsResources>(
      value: ref.watch(awsResourcesProvider(key)),
      onRetry: () => ref.invalidate(awsResourcesProvider(key)),
      builder: (data) => ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
        _MapBanner(status: data.map),
        _Summary(data: data),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: context.s.awsFilterHint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => filter = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        if (data.unmapped.isNotEmpty) _UnmappedSection(items: _filterUnmapped(data.unmapped)),
        ..._groups(data.resources),
        if (data.resources.isEmpty && data.unmapped.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.s.noAwsResources),
          ),
        if (data.helpers.isNotEmpty || data.data.isNotEmpty)
          _OthersSection(helpers: data.helpers, data: data.data),
      ]),
    );
  }

  List<UnmappedResource> _filterUnmapped(List<UnmappedResource> all) => filter.isEmpty
      ? all
      : all
          .where((u) => '${u.address} ${u.tfType} ${reasonLabel(context, u.reason)}'.toLowerCase().contains(filter))
          .toList();

  bool _matches(AwsResource r) =>
      filter.isEmpty ||
      '${r.cfnType} ${r.name} ${r.identity} ${r.all.map((c) => '${c.address} ${c.tfType}').join(' ')}'
          .toLowerCase()
          .contains(filter);

  List<Widget> _groups(List<AwsResource> all) {
    final byType = <String, List<AwsResource>>{};
    for (final r in all.where(_matches)) {
      byType.putIfAbsent(r.cfnType, () => []).add(r);
    }
    return [
      for (final e in byType.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: filter.isNotEmpty || byType.length <= 4,
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.cloud_outlined),
              title: Text(e.key, style: Theme.of(context).textTheme.titleSmall),
              trailing: Tag('${e.value.length}'),
              children: [for (final r in e.value) _AwsResourceTile(r: r)],
            ),
          ),
        ),
    ];
  }
}

class _MapBanner extends StatelessWidget {
  const _MapBanner({required this.status});
  final AwsMapStatus status;

  @override
  Widget build(BuildContext context) {
    if (!status.needsAttention) return const SizedBox.shrink();
    final s = context.s;
    final (String text, Color color, IconData icon) = status.unavailable
        ? (
            s.mapUnavailableBanner,
            Palette.locked,
            Icons.error_outline
          )
        : status.state == 'degraded'
            ? (
                s.mapDegradedBanner(status.issues.length),
                Palette.modified,
                Icons.warning_amber_rounded
              )
            : (
                s.mapStaleBanner(status.staleAfterDays, status.reviewedAt ?? s.unknownDate),
                Palette.modified,
                Icons.history_toggle_off
              );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        child: ListTile(leading: Icon(icon, color: color), title: Text(text)),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.data});
  final AwsResources data;

  @override
  Widget build(BuildContext context) {
    final c = data.coverage;
    final s = context.s;
    Widget tile(Widget child) => SizedBox(width: 230, child: child);
    return Wrap(spacing: 12, runSpacing: 12, children: [
      tile(StatCard(label: s.statAwsResources, value: '${c.awsResources}', icon: Icons.cloud_outlined)),
      tile(StatCard(
        label: s.statMapped,
        value: s.statMappedValue(c.mapped, c.managedTotal),
        icon: Icons.account_tree_outlined,
        color: Palette.of(1),
      )),
      tile(StatCard(
        label: s.statUnmapped,
        value: '${c.unmapped}',
        icon: Icons.help_outline,
        color: c.unmapped == 0 ? Palette.released : Palette.modified,
      )),
    ]);
  }
}

class _AwsResourceTile extends StatelessWidget {
  const _AwsResourceTile({required this.r});
  final AwsResource r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final count = r.all.length;
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(r.name, style: t.titleSmall),
        if (r.provisional) Tag(context.s.provisionalTag),
      ]),
      subtitle: SelectableText(r.identity, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
      trailing: Tag(context.s.terraformElements(count), icon: Icons.layers_outlined),
      childrenPadding: const EdgeInsets.fromLTRB(32, 0, 16, 8),
      children: [
        for (final c in r.all)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(r.primaries.contains(c) ? Icons.star_border : Icons.subdirectory_arrow_right, size: 18),
            title: Text(c.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            subtitle: Text(c.cfnType != null && !r.primaries.contains(c) ? '${c.tfType} · ${c.cfnType}' : c.tfType),
          ),
      ],
    );
  }
}

class _UnmappedSection extends StatelessWidget {
  const _UnmappedSection({required this.items});
  final List<UnmappedResource> items;

  @override
  Widget build(BuildContext context) {
    final color = Palette.modified;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: color.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(Icons.help_outline, color: color),
          title: Text(context.s.statUnmapped, style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(context.s.unmappedSubtitle),
          trailing: Tag('${items.length}', color: color),
          children: [
            for (final u in items)
              ListTile(
                dense: true,
                title: Text(u.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                subtitle: Text('${u.tfType} · ${reasonLabel(context, u.reason)}${u.detail.isEmpty ? '' : ' (${u.detail})'}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _OthersSection extends StatelessWidget {
  const _OthersSection({required this.helpers, required this.data});
  final List<AwsComponent> helpers;
  final List<AwsComponent> data;

  @override
  Widget build(BuildContext context) {
    Widget block(String title, List<AwsComponent> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(title, style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final c in items)
              ListTile(
                dense: true,
                title: Text(c.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                subtitle: Text(c.tfType),
              ),
          ]);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.build_outlined),
        title: Text(context.s.othersTitle, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(context.s.othersSubtitle),
        trailing: Tag('${helpers.length + data.length}'),
        children: [
          block(context.s.utilitiesBlock, helpers),
          block(context.s.dataSourcesBlock, data),
        ],
      ),
    );
  }
}
