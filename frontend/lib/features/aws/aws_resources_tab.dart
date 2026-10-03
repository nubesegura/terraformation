import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

/// Motivos por los que un recurso no se pudo asociar a un recurso AWS.
const unmappedReasons = {
  'no_rule': 'Tipo sin regla en el mapa',
  'non_aws_provider': 'Proveedor distinto de AWS',
  'missing_identity': 'Sin identificador utilizable',
  'missing_parent_ref': 'Sin referencia a su recurso padre',
  'orphan_child': 'Su recurso padre no está en este state',
  'ambiguous_parent': 'Coincide con más de un recurso padre',
  'invalid_map_entry': 'Regla inválida en el mapa',
  'map_unavailable': 'El mapa no se pudo cargar',
};

String reasonLabel(String reason) => unmappedReasons[reason] ?? reason;

/// Vista principal: los recursos AWS que despliega el state, agrupados por tipo de CloudFormation.
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
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Filtrar por nombre, identificador, tipo o recurso de Terraform',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => filter = v.trim().toLowerCase()),
        ),
        const SizedBox(height: 12),
        if (data.unmapped.isNotEmpty) _UnmappedSection(items: _filterUnmapped(data.unmapped)),
        ..._groups(data.resources),
        if (data.resources.isEmpty && data.unmapped.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Este state no contiene recursos AWS gestionados.'),
          ),
        if (data.helpers.isNotEmpty || data.data.isNotEmpty)
          _OthersSection(helpers: data.helpers, data: data.data),
      ]),
    );
  }

  List<UnmappedResource> _filterUnmapped(List<UnmappedResource> all) => filter.isEmpty
      ? all
      : all
          .where((u) => '${u.address} ${u.tfType} ${reasonLabel(u.reason)}'.toLowerCase().contains(filter))
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
    final (String text, Color color, IconData icon) = status.unavailable
        ? (
            'El mapa de recursos no se pudo cargar: ningún recurso se puede asociar a AWS y todo aparece como "Sin mapear".',
            Palette.locked,
            Icons.error_outline
          )
        : status.state == 'degraded'
            ? (
                'Hay ${status.issues.length} regla(s) inválida(s) en el mapa; los tipos afectados aparecen como "Sin mapear".',
                Palette.modified,
                Icons.warning_amber_rounded
              )
            : (
                'El mapa lleva más de ${status.staleAfterDays} días sin revisarse '
                    '(última revisión: ${status.reviewedAt ?? 'desconocida'}). '
                    'Pueden faltar tipos nuevos: revisa la sección "Sin mapear".',
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
    Widget tile(Widget child) => SizedBox(width: 230, child: child);
    return Wrap(spacing: 12, runSpacing: 12, children: [
      tile(StatCard(label: 'Recursos AWS', value: '${c.awsResources}', icon: Icons.cloud_outlined)),
      tile(StatCard(
        label: 'Elementos de Terraform mapeados',
        value: '${c.mapped} de ${c.managedTotal}',
        icon: Icons.account_tree_outlined,
        color: Palette.of(1),
      )),
      tile(StatCard(
        label: 'Sin mapear',
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
        if (r.provisional) const Tag('regla provisional'),
      ]),
      subtitle: SelectableText(r.identity, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
      trailing: Tag('$count elemento${count == 1 ? '' : 's'} de Terraform', icon: Icons.layers_outlined),
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
          title: Text('Sin mapear', style: Theme.of(context).textTheme.titleSmall),
          subtitle: const Text(
            'Recursos que el mapa no pudo asociar con certeza a un recurso AWS. No se adivinan por nombre.',
          ),
          trailing: Tag('${items.length}', color: color),
          children: [
            for (final u in items)
              ListTile(
                dense: true,
                title: Text(u.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                subtitle: Text('${u.tfType} · ${reasonLabel(u.reason)}${u.detail.isEmpty ? '' : ' (${u.detail})'}'),
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
        title: Text('Utilidades y datos de Terraform', style: Theme.of(context).textTheme.titleSmall),
        subtitle: const Text('No crean recursos AWS: contraseñas aleatorias, esperas, data sources, etc.'),
        trailing: Tag('${helpers.length + data.length}'),
        children: [
          block('Utilidades (random, time, null, tls…)', helpers),
          block('Data sources (solo lectura)', data),
        ],
      ),
    );
  }
}
