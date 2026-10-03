import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../l10n/app_strings.dart';

class StateTab extends ConsumerStatefulWidget {
  const StateTab({super.key, required this.stateRef, required this.initialVersion});
  final StateRef stateRef;
  final String initialVersion;

  @override
  ConsumerState<StateTab> createState() => _StateTabState();
}

class _StateTabState extends ConsumerState<StateTab> {
  late String version = widget.initialVersion;

  @override
  void didUpdateWidget(covariant StateTab old) {
    super.didUpdateWidget(old);
    if (old.initialVersion != widget.initialVersion) version = widget.initialVersion;
  }

  @override
  Widget build(BuildContext context) {
    final vkey = widget.stateRef;
    final versions = ref.watch(versionsProvider(vkey));
    final detail = ref.watch(stateDetailProvider((widget.stateRef, version)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: versions.when(
          data: (list) {
            final readable = list.items.where((v) => v.readable).toList();
            final ids = readable.map((v) => v.versionId).toSet();
            final selected = ids.contains(version) ? version : (readable.isEmpty ? null : readable.first.versionId);
            return SizedBox(
              width: 460,
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.s.stateVersionLabel, isDense: true, border: const OutlineInputBorder()),
                items: [
                  for (final v in readable)
                    DropdownMenuItem(
                      value: v.versionId,
                      child: Text('#${v.serial} · ${shortDateTime(v.lastModified)} · TF ${v.terraformVersion}${v.isCurrent ? ' · ${context.s.currentTag}' : ''}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => version = v ?? version),
              ),
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
      ),
      Expanded(
        child: AsyncView<StateDetail>(
          value: detail,
          onRetry: () => ref.invalidate(stateDetailProvider((widget.stateRef, version))),
          builder: (d) => _StateBody(d: d),
        ),
      ),
    ]);
  }
}

class _StateBody extends StatefulWidget {
  const _StateBody({required this.d});
  final StateDetail d;
  @override
  State<_StateBody> createState() => _StateBodyState();
}

class _StateBodyState extends State<_StateBody> {
  String filter = '';
  String? module;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final f = filter.toLowerCase();
    final res = d.resources.where((r) {
      if (module != null && r.module != module) return false;
      if (f.isEmpty) return true;
      return r.address.toLowerCase().contains(f) ||
          r.attributes.entries.any((e) => e.key.toLowerCase().contains(f) || e.value.toLowerCase().contains(f));
    }).toList();
    return ListView(children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        Tag('Terraform ${d.info.terraformVersion}', icon: Icons.terminal),
        Tag('serial ${d.info.serial}'),
        Tag('lineage ${shortId(d.info.lineage)}…', icon: Icons.fingerprint),
        Tag(s.resourcesCount(d.info.resourceCount)),
        Tag('s3://${d.info.s3Bucket}/${d.info.s3Key}', icon: Icons.cloud_outlined),
        Tag(shortDateTime(d.info.lastModified), icon: Icons.schedule),
      ]),
      const SizedBox(height: 14),
      if (d.outputs.isNotEmpty)
        SectionCard(
          title: s.outputsTitle(d.outputs.length),
          child: Column(children: [
            for (final o in d.outputs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(o.sensitive ? Icons.visibility_off_outlined : Icons.output, size: 18),
                title: Text(o.name),
                subtitle: SelectableText(o.value, maxLines: 3, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                trailing: o.sensitive ? Tag(s.sensitiveTag, color: Palette.modified) : null,
              ),
          ]),
        ),
      const SizedBox(height: 12),
      SectionCard(
        title: s.modulesTitle,
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          ChoiceChip(label: Text(s.allLabel), selected: module == null, onSelected: (_) => setState(() => module = null)),
          for (final m in d.modules)
            ChoiceChip(
              label: Text('${m.path} (${m.resourceCount})'),
              selected: module == m.path,
              onSelected: (_) => setState(() => module = module == m.path ? null : m.path),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text(s.resourcesTitle(res.length), style: t.titleMedium)),
        SizedBox(
          width: 280,
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.filterAddressOrAttr, isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => setState(() => filter = v),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      for (final r in res.take(400)) _ResourceTile(r: r),
      if (res.length > 400)
        Padding(padding: const EdgeInsets.all(12), child: Text(s.showingFirst400(res.length))),
    ]);
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({required this.r});
  final ResourceInstance r;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        dense: true,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(r.mode == 'data' ? Icons.search : Icons.widgets_outlined, size: 18),
        title: Text(r.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
        subtitle: Wrap(spacing: 6, children: [
          Tag(r.type),
          Tag(r.provider),
          if (r.status != null) Tag(r.status!, color: Palette.modified),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (r.dependencies.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  Text(context.s.dependsOn),
                  for (final dep in r.dependencies) Tag(dep, icon: Icons.subdirectory_arrow_right),
                ]),
              ),
            ),
          Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
            children: [
              for (final e in r.attributes.entries)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SelectableText(e.key, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600))),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SelectableText(e.value, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: e.value == '(sensitive)' ? Palette.modified : null))),
                ]),
            ],
          ),
        ],
      ),
    );
  }
}
