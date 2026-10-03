import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

class LocksPage extends ConsumerWidget {
  const LocksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Locks activos', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          AsyncView<ActiveLocks>(
            value: ref.watch(activeLocksProvider),
            onRetry: () => ref.invalidate(activeLocksProvider),
            builder: (l) => l.items.isEmpty
                ? const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Row(children: [
                        Icon(Icons.lock_open, color: Palette.released),
                        SizedBox(width: 12),
                        Text('Ningún proyecto está bloqueado.'),
                      ]),
                    ),
                  )
                : Column(children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Se alerta cuando un lock supera ${l.thresholdMinutes} min.', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    const SizedBox(height: 8),
                    for (final lk in l.items)
                      Card(
                        color: lk.alert ? Palette.locked.withValues(alpha: 0.08) : null,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(lk.alert ? Icons.warning_amber_rounded : Icons.lock, color: lk.alert ? Palette.locked : Palette.modified),
                          title: Text(stateLabel(lk.stateRef)),
                          subtitle: Text('${lk.who} · ${lk.operation.replaceFirst('OperationType', '')} · desde ${shortDateTime(lk.since)} (${formatDuration(lk.durationS)})'),
                          trailing: lk.alert ? const Tag('Alerta', color: Palette.locked) : null,
                          onTap: () => context.go(stateLocation(lk.stateRef, extra: {'tab': 'locks'})),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
