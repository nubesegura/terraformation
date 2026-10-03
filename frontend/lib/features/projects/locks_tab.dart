import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

class LocksTab extends ConsumerWidget {
  const LocksTab({super.key, required this.stateRef});
  final StateRef stateRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = stateRef;
    return AsyncView<LockHistory>(
      value: ref.watch(projectLocksProvider(key)),
      onRetry: () => ref.invalidate(projectLocksProvider(key)),
      builder: (h) => ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
        _CurrentLock(lock: h.current),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Historial de locks (${h.items.length})',
          child: h.items.isEmpty
              ? const Text('No se registraron locks. Si usas el backend S3, revisa que `use_lockfile = true`.')
              : Column(children: [for (final r in h.items) _LockRow(r: r)]),
        ),
      ]),
    );
  }
}

class _CurrentLock extends StatelessWidget {
  const _CurrentLock({required this.lock});
  final LockInfo lock;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (String title, String body, Color color) = switch (lock.status) {
      'locked' => (
          lock.alert ? 'Bloqueado — alerta por duración' : 'Bloqueado',
          '${lock.who} · ${lock.operation.replaceFirst('OperationType', '')} · desde ${shortDateTime(lock.since)} (${formatDuration(lock.durationS)})',
          Palette.locked
        ),
      'released' => ('Liberado', 'Último lock de ${lock.who.isEmpty ? '—' : lock.who}, liberado ${relativeTime(lock.releasedAt)}', Palette.released),
      _ => (
          'Sin locking detectado',
          'Nunca se vio un .tflock para este state. Posible falta de use_lockfile = true en el backend.',
          Palette.unknown
        ),
    };
    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          LockBadge(lock: lock),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium),
            Text(body, style: t.bodyMedium),
          ])),
        ]),
      ),
    );
  }
}

class _LockRow extends StatelessWidget {
  const _LockRow({required this.r});
  final LockRecord r;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(r.active ? Icons.lock : Icons.lock_open, color: r.active ? (r.alert ? Palette.locked : Palette.modified) : Palette.released),
      title: Text('${r.who} · ${r.operation.replaceFirst('OperationType', '')}'),
      subtitle: Text(
          '${shortDateTime(r.acquiredAt)} > ${r.active ? 'activo' : shortDateTime(r.releasedAt)} · ${formatDuration(r.durationS)}${r.terraformVersion.isEmpty ? '' : ' · TF ${r.terraformVersion}'}'),
      trailing: r.alert ? const Tag('Alerta', color: Palette.locked) : Text(shortId(r.lockId), style: const TextStyle(fontSize: 11)),
    );
  }
}
