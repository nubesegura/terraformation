import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth.dart';
import 'core/config.dart';
import 'core/platform/browser.dart';
import 'l10n/app_strings.dart';
import 'l10n/lang_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = await AppConfig.load();
    final container = ProviderContainer(overrides: [configProvider.overrideWithValue(config)]);
    // Handles ?code= (Cognito callback) or restores the session before mounting the router.
    await container.read(authProvider.notifier).init();
    runApp(UncontrolledProviderScope(container: container, child: const TerraformationApp()));
  } catch (e) {
    final s = AppStrings(AppLang.fromCode(createBrowser().getLocal(kLangStorageKey)));
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s.startupFailed('$e')))),
      ),
    ));
  }
}
