import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraformation_web/core/api/models.dart';
import 'package:terraformation_web/shared/widgets.dart';

Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: Center(child: w)));

void main() {
  testWidgets('LockBadge distingue bloqueado, liberado y sin locking detectado', (t) async {
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'locked', who: 'ana'))));
    expect(find.text('Bloqueado'), findsOneWidget);
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'locked', alert: true))));
    expect(find.text('Bloqueado (alerta)'), findsOneWidget);
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'released'))));
    expect(find.text('Liberado'), findsOneWidget);
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'none_detected'))));
    expect(find.text('Sin locking detectado'), findsOneWidget);
  });

  testWidgets('ChangeCounts muestra +/−/~', (t) async {
    await t.pumpWidget(wrap(const ChangeCounts(added: 2, removed: 1, modified: 3)));
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);
    expect(find.text('~3'), findsOneWidget);
  });

  testWidgets('AsyncView muestra el error con reintento', (t) async {
    var retried = false;
    await t.pumpWidget(wrap(AsyncView<int>(
      value: AsyncValue<int>.error('boom', StackTrace.empty),
      builder: (_) => const Text('ok'),
      onRetry: () => retried = true,
    )));
    expect(find.text('boom'), findsOneWidget);
    await t.tap(find.text('Reintentar'));
    expect(retried, isTrue);
  });
}
