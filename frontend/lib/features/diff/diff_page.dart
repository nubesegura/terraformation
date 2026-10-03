import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../l10n/lang_provider.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../l10n/app_strings.dart';

class DiffPage extends ConsumerWidget {
  const DiffPage({super.key, required this.stateRef, this.from, this.to});
  final StateRef stateRef;
  final String? from;
  final String? to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(versionsProvider(stateRef));
    return AsyncView<VersionList>(
      value: versions,
      onRetry: () => ref.invalidate(versionsProvider(stateRef)),
      builder: (list) {
        final states = list.items.where((v) => v.readable).toList();
        if (states.length < 2) {
          return Center(child: Text(context.s.needTwoReadable));
        }
        final toId = to ?? states.first.versionId;
        final fromId = from ?? (states.length > 1 ? states[1].versionId : states.first.versionId);
        return _DiffScaffold(
          stateRef: stateRef,
          versions: states,
          from: fromId,
          to: toId,
        );
      },
    );
  }
}

class _DiffScaffold extends ConsumerWidget {
  const _DiffScaffold({
    required this.stateRef,
    required this.versions,
    required this.from,
    required this.to,
  });
  final StateRef stateRef;
  final List<VersionInfo> versions;
  final String from;
  final String to;

  void _go(BuildContext context, String f, String t) =>
      context.go(stateLocation(stateRef, sub: 'diff', extra: {'from': f, 'to': t}));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.s;
    final diff = ref.watch(diffProvider((stateRef, from, to)));
    Widget picker(String label, String value, void Function(String) onChanged) => SizedBox(
          width: 320,
          child: DropdownButtonFormField<String>(
            initialValue: versions.any((v) => v.versionId == value) ? value : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
            items: [
              for (final v in versions)
                DropdownMenuItem(
                  value: v.versionId,
                  child: Text('#${v.serial} · ${shortDateTime(v.lastModified)} · ${shortId(v.versionId)}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
        );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            tooltip: s.backToProject,
            onPressed: () => context.go(stateLocation(stateRef, extra: {'tab': 'timeline'})),
            icon: const Icon(Icons.arrow_back),
          ),
          Text(s.compareVersionsTitle(stateLabel(stateRef)), style: Theme.of(context).textTheme.titleLarge),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          picker(s.fromOlder, from, (v) => _go(context, v, to)),
          IconButton(
            tooltip: s.swap,
            onPressed: () => _go(context, to, from),
            icon: const Icon(Icons.swap_horiz),
          ),
          picker(s.toNewer, to, (v) => _go(context, from, v)),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView<StateDiff>(
            value: diff,
            onRetry: () => ref.invalidate(diffProvider((stateRef, from, to))),
            builder: (d) => DiffView(diff: d, stateRef: stateRef),
          ),
        ),
      ]),
    );
  }
}

class DiffView extends ConsumerStatefulWidget {
  const DiffView({super.key, required this.diff, required this.stateRef});
  final StateDiff diff;
  final StateRef stateRef;

  @override
  ConsumerState<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends ConsumerState<DiffView> {
  bool sideBySide = true;
  String filter = '';
  String? aiText;
  String? aiError;
  bool aiBusy = false;

  Future<void> _summarize() async {
    final s = context.s;
    final language = ref.read(langProvider).name;
    setState(() {
      aiBusy = true;
      aiError = null;
    });
    try {
      final r = await ref
          .read(apiClientProvider)
          .diffSummary(widget.stateRef, widget.diff.from.versionId, widget.diff.to.versionId, language: language);
      setState(() => aiText = r.summary);
    } on ApiException catch (e) {
      setState(() => aiError = e.status == 501 ? s.aiDisabled : e.detail);
    } finally {
      if (mounted) setState(() => aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diff;
    final s = context.s;
    bool match(String a) => filter.isEmpty || a.toLowerCase().contains(filter.toLowerCase());
    final added = d.added.where((r) => match(r.address)).toList();
    final removed = d.removed.where((r) => match(r.address)).toList();
    final modified = d.modified.where((r) => match(r.address)).toList();
    return ListView(children: [
      Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Tag(s.diffAdded(d.summary.added), color: Palette.added, icon: Icons.add_circle_outline),
        Tag(s.diffRemoved(d.summary.removed), color: Palette.removed, icon: Icons.remove_circle_outline),
        Tag(s.diffModified(d.summary.modified), color: Palette.modified, icon: Icons.edit_outlined),
        Tag(s.diffUnchanged(d.summary.unchanged)),
        Tag('serial ${d.from.serial} > ${d.to.serial}'),
        if (d.from.terraformVersion != d.to.terraformVersion)
          Tag('Terraform ${d.from.terraformVersion} > ${d.to.terraformVersion}', color: Palette.modified),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: InputDecoration(
                prefixIcon: const Icon(Icons.filter_alt_outlined), hintText: s.filterResources, isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => setState(() => filter = v),
          ),
        ),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(s.sideBySide), icon: const Icon(Icons.view_column_outlined)),
            ButtonSegment(value: false, label: Text(s.unified), icon: const Icon(Icons.view_stream_outlined)),
          ],
          selected: {sideBySide},
          onSelectionChanged: (s) => setState(() => sideBySide = s.first),
        ),
        FilledButton.tonalIcon(
          onPressed: aiBusy ? null : _summarize,
          icon: aiBusy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(s.summarizeWithAi),
        ),
      ]),
      if (aiText != null || aiError != null) ...[
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(aiText ?? aiError!),
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (d.outputs.isNotEmpty)
        _Group(
          title: s.outputsTitle(d.outputs.length),
          color: Palette.modified,
          children: [
            for (final o in d.outputs)
              _KeyRow(label: o.name, oldValue: o.oldValue, newValue: o.newValue, kind: o.kind),
          ],
        ),
      if (added.isNotEmpty)
        _Group(
          title: s.groupAdded(added.length),
          color: Palette.added,
          children: [for (final r in added) _ResourceBlock(r: r, kind: 'added')],
        ),
      if (removed.isNotEmpty)
        _Group(
          title: s.groupRemoved(removed.length),
          color: Palette.removed,
          children: [for (final r in removed) _ResourceBlock(r: r, kind: 'removed')],
        ),
      if (modified.isNotEmpty)
        _Group(
          title: s.groupModified(modified.length),
          color: Palette.modified,
          children: [for (final r in modified) _ModifiedBlock(r: r, sideBySide: sideBySide)],
        ),
      if (added.isEmpty && removed.isEmpty && modified.isEmpty && d.outputs.isEmpty)
        Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(s.noDifferences))),
    ]);
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.color, required this.children});
  final String title;
  final Color color;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 4, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 8),
              ...children,
            ]),
          ),
        ),
      );
}

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4);

Color _bg(String kind, {bool strong = false}) {
  final base = switch (kind) {
    'added' => Palette.added,
    'removed' => Palette.removed,
    _ => Palette.modified,
  };
  return base.withValues(alpha: strong ? 0.22 : 0.12);
}

class _ResourceBlock extends StatelessWidget {
  const _ResourceBlock({required this.r, required this.kind});
  final ResourceChange r;
  final String kind;
  @override
  Widget build(BuildContext context) {
    final sign = kind == 'added' ? '+' : '−';
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      leading: Text(sign, style: _mono.copyWith(fontSize: 18, color: kind == 'added' ? Palette.added : Palette.removed)),
      title: Text(r.address, style: _mono),
      children: [
        for (final e in r.attributes.entries)
          Container(
            color: _bg(kind),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: SelectableText('$sign ${e.key} = "${e.value}"', style: _mono),
          ),
      ],
    );
  }
}

class _ModifiedBlock extends StatelessWidget {
  const _ModifiedBlock({required this.r, required this.sideBySide});
  final ResourceModified r;
  final bool sideBySide;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      leading: Text('~', style: _mono.copyWith(fontSize: 18, color: Palette.modified)),
      title: Text(r.address, style: _mono),
      subtitle: Text(
        [
          context.s.attributesCount(r.changes.length),
          if (r.sensitiveChanged) context.s.sensitiveValueChanged,
          if (r.dependenciesChanged) context.s.dependenciesChanged,
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        if (r.changes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(context.s.sensitiveOrDepsNote),
          )
        else if (sideBySide)
          _SideBySide(changes: r.changes)
        else
          _Unified(text: r.unifiedDiff),
      ],
    );
  }
}

class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.changes});
  final List<AttrChange> changes;

  @override
  Widget build(BuildContext context) {
    Widget cell(String? text, Color? bg) => Expanded(
          child: Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: SelectableText(text ?? '', style: _mono),
          ),
        );
    return Column(children: [
      for (final c in changes)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 200,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(c.key, style: _mono.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              ),
            ),
            cell(c.oldValue == null ? null : '− ${c.oldValue}', c.oldValue == null ? null : _bg('removed')),
            const SizedBox(width: 2),
            cell(c.newValue == null ? null : '+ ${c.newValue}', c.newValue == null ? null : _bg('added')),
          ]),
        ),
    ]);
  }
}

class _Unified extends StatelessWidget {
  const _Unified({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in lines)
          if (l.isNotEmpty)
            Container(
              color: l.startsWith('+') && !l.startsWith('+++')
                  ? _bg('added')
                  : l.startsWith('-') && !l.startsWith('---')
                      ? _bg('removed')
                      : l.startsWith('@@')
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
                          : null,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: SelectableText(l, style: _mono),
            ),
      ]),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.label, this.oldValue, this.newValue, required this.kind});
  final String label;
  final String? oldValue;
  final String? newValue;
  final String kind;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 200, child: Text(label, style: _mono.copyWith(fontWeight: FontWeight.w600))),
          if (oldValue != null)
            Expanded(child: Container(color: _bg('removed'), padding: const EdgeInsets.all(3), child: SelectableText('− $oldValue', style: _mono))),
          const SizedBox(width: 2),
          if (newValue != null)
            Expanded(child: Container(color: _bg('added'), padding: const EdgeInsets.all(3), child: SelectableText('+ $newValue', style: _mono))),
        ]),
      );
}
