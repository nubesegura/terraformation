import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terraformation_web/core/auth/auth.dart';
import 'package:terraformation_web/core/platform/browser_stub.dart';
import 'package:terraformation_web/l10n/app_strings.dart';
import 'package:terraformation_web/l10n/lang_provider.dart';
import 'package:terraformation_web/l10n/language_button.dart';

ProviderContainer make(MemoryBrowser b) =>
    ProviderContainer(overrides: [browserProvider.overrideWithValue(b)]);

Widget app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          builder: (context, child) =>
              AppStringsScope(strings: ref.watch(stringsProvider), child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            appBar: AppBar(actions: const [LanguageButton()]),
            body: Builder(builder: (context) => Text(context.s.navProjects)),
          ),
        ),
      ),
    );

void main() {
  test('English is the default language and sets the document language', () {
    final b = MemoryBrowser();
    final c = make(b);
    expect(c.read(langProvider), AppLang.en);
    expect(c.read(stringsProvider).navProjects, 'Projects');
    expect(b.documentLang, 'en');
  });

  test('the chosen language is stored and restored', () {
    final b = MemoryBrowser();
    make(b).read(langProvider.notifier).set(AppLang.es);
    expect(b.getLocal(kLangStorageKey), 'es');
    expect(b.documentLang, 'es');
    final again = make(b);
    expect(again.read(langProvider), AppLang.es);
    expect(again.read(stringsProvider).navProjects, 'Proyectos');
  });

  test('an unknown stored language falls back to English', () {
    final b = MemoryBrowser()..setLocal(kLangStorageKey, 'fr');
    expect(make(b).read(langProvider), AppLang.en);
  });

  test('parametrized strings are translated and interpolated', () {
    const en = AppStrings(AppLang.en);
    const es = AppStrings(AppLang.es);
    expect(en.resourcesCount(3), '3 resources');
    expect(es.resourcesCount(3), '3 recursos');
    expect(en.agoHours(4), '4 h ago');
    expect(es.agoHours(4), 'hace 4 h');
    expect(en.unmappedReason('orphan_child'), isNot(es.unmappedReason('orphan_child')));
    expect(en.unmappedReason('unknown_code'), 'unknown_code');
  });

  testWidgets('the language button switches the UI language without reloading', (t) async {
    final c = make(MemoryBrowser());
    await t.pumpWidget(app(c));
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);

    await t.tap(find.byType(LanguageButton));
    await t.pumpAndSettle();
    await t.tap(find.text('ES · Español'));
    await t.pumpAndSettle();

    expect(find.text('Proyectos'), findsOneWidget);
    expect(find.text('Projects'), findsNothing);
    expect(find.text('ES'), findsOneWidget);
    expect(c.read(langProvider), AppLang.es);
  });
}
