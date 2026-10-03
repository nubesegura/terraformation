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

class TimelineTab extends ConsumerStatefulWidget {
  const TimelineTab({super.key, required this.stateRef});
  final StateRef stateRef;

  @override
  ConsumerState<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends ConsumerState<TimelineTab> {
  final List<String> _picked = [];

  void _toggle(String id) => setState(() {
        if (_picked.contains(id)) {
          _picked.remove(id);
        } else {
          if (_picked.length == 2) _picked.removeAt(0);
          _picked.add(id);
        }
      });

  @override
  Widget build(BuildContext context) {
    final key = widget.stateRef;
    final timeline = ref.watch(timelineProvider(key));
    return AsyncView<Timeline>(
      value: timeline,
      onRetry: () => ref.invalidate(timelineProvider(key)),
      builder: (tl) {
        final versions = tl.items.where((e) => e.type == 'version').toList();
        String? previousOf(String id) {
          final i = versions.indexWhere((v) => v.versionId == id);
          return (i >= 0 && i + 1 < versions.length) ? versions[i + 1].versionId : null;
        }

        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                child: Text(
                  _picked.length == 2 ? context.s.twoSelected : context.s.pickTwoVersions,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              FilledButton.icon(
                onPressed: _picked.length == 2
                    ? () {
                        final sorted = [..._picked]..sort((a, b) {
                            final ia = versions.indexWhere((v) => v.versionId == a);
                            final ib = versions.indexWhere((v) => v.versionId == b);
                            return ib.compareTo(ia); // oldest first
                          });
                        context.go(stateLocation(widget.stateRef,
                            sub: 'diff', extra: {'from': sorted[0], 'to': sorted[1]}));
                      }
                    : null,
                icon: const Icon(Icons.compare_arrows),
                label: Text(context.s.compare),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tl.items.length,
              itemBuilder: (context, i) {
                final e = tl.items[i];
                return _TimelineRow(
                  e: e,
                  first: i == 0,
                  last: i == tl.items.length - 1,
                  picked: e.versionId != null && _picked.contains(e.versionId),
                  onPick: e.type == 'version' ? () => _toggle(e.versionId!) : null,
                  onOpen: e.type == 'version'
                      ? () => context.go(stateLocation(widget.stateRef,
                          extra: {'tab': 'state', 'version': e.versionId!}))
                      : null,
                  onVsPrevious: e.type == 'version' && previousOf(e.versionId!) != null
                      ? () => context.go(stateLocation(widget.stateRef,
                          sub: 'diff', extra: {'from': previousOf(e.versionId!)!, 'to': e.versionId!}))
                      : null,
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.e,
    required this.first,
    required this.last,
    required this.picked,
    this.onPick,
    this.onOpen,
    this.onVsPrevious,
  });
  final TimelineEvent e;
  final bool first;
  final bool last;
  final bool picked;
  final VoidCallback? onPick;
  final VoidCallback? onOpen;
  final VoidCallback? onVsPrevious;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;
    final (IconData icon, Color color, String title) = switch (e.type) {
      'version' => (Icons.commit, Theme.of(context).colorScheme.primary, s.timelineVersion(e.serial ?? 0, e.terraformVersion ?? '')),
      'delete_marker' => (Icons.delete_outline, Palette.removed, s.timelineDeleteMarker),
      'lock_acquired' => (Icons.lock, Palette.locked, s.timelineLockAcquired(e.who ?? '')),
      _ => (Icons.lock_open, Palette.released, e.durationS != null ? s.timelineLockReleasedAfter(formatDuration(e.durationS)) : s.timelineLockReleased),
    };
    final isLock = e.type.startsWith('lock');
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 44,
          child: Column(children: [
            Expanded(child: Container(width: 2, color: first ? Colors.transparent : Theme.of(context).dividerColor)),
            Container(
              padding: EdgeInsets.all(isLock ? 4 : 6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color)),
              child: Icon(icon, size: isLock ? 14 : 18, color: color),
            ),
            Expanded(child: Container(width: 2, color: last ? Colors.transparent : Theme.of(context).dividerColor)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: isLock ? 4 : 8),
            child: Card(
              color: picked ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
              child: Padding(
                padding: EdgeInsets.all(isLock ? 8 : 12),
                child: Row(children: [
                  if (onPick != null) Checkbox(value: picked, onChanged: (_) => onPick!()),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: isLock ? t.bodyMedium : t.titleSmall),
                      Text('${shortDateTime(e.timestamp)} · ${relativeTime(s, e.timestamp)}', style: t.bodySmall),
                      if (isLock && e.operation != null)
                        Text(e.operation!.replaceFirst('OperationType', ''), style: t.bodySmall),
                      if (e.type == 'version') ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          ChangeCounts(added: e.added ?? 0, removed: e.removed ?? 0, modified: e.modified ?? 0),
                          Tag(s.resourcesCount(e.resourceCount ?? 0)),
                          Tag(shortId(e.versionId ?? ''), icon: Icons.tag),
                        ]),
                      ],
                    ]),
                  ),
                  if (onOpen != null)
                    TextButton(onPressed: onOpen, child: Text(s.view)),
                  if (onVsPrevious != null)
                    TextButton(onPressed: onVsPrevious, child: Text(s.vsPrevious)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
