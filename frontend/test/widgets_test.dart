import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraformation_web/core/api/models.dart';
import 'package:terraformation_web/l10n/app_strings.dart';
import 'package:terraformation_web/shared/widgets.dart';

Widget wrap(Widget w, {AppLang lang = AppLang.en}) => MaterialApp(
      home: AppStringsScope(
        strings: AppStrings(lang),
        child: Scaffold(body: Center(child: w)),
      ),
    );

void main() {
  testWidgets('LockBadge tells locked, released and no locking detected apart', (t) async {
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'locked', who: 'ana'))));
    expect(find.text('Locked'), findsOneWidget);
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'locked', alert: true))));
    expect(find.text('Locked (alert)'), findsOneWidget);
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'released'))));
    expect(find.text('Released'), findsOneWidget);
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'none_detected'))));
    expect(find.text('No locking detected'), findsOneWidget);
  });

  testWidgets('LockBadge is shown in Spanish when the language is Spanish', (t) async {
    await t.pumpWidget(wrap(const LockBadge(lock: LockInfo(status: 'released')), lang: AppLang.es));
    expect(find.text('Liberado'), findsOneWidget);
    expect(find.text('Released'), findsNothing);
  });

  testWidgets('ChangeCounts shows +/−/~', (t) async {
    await t.pumpWidget(wrap(const ChangeCounts(added: 2, removed: 1, modified: 3)));
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);
    expect(find.text('~3'), findsOneWidget);
  });

  testWidgets('AsyncView shows the error with a retry button', (t) async {
    var retried = false;
    await t.pumpWidget(wrap(AsyncView<int>(
      value: AsyncValue<int>.error('boom', StackTrace.empty),
      builder: (_) => const Text('ok'),
      onRetry: () => retried = true,
    )));
    expect(find.text('boom'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
