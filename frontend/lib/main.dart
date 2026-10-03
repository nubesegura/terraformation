import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth/auth.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = await AppConfig.load();
    final container = ProviderContainer(overrides: [configProvider.overrideWithValue(config)]);
    // Procesa ?code= (retorno de Cognito) o restaura la sesión antes de montar el router.
    await container.read(authProvider.notifier).init();
    runApp(UncontrolledProviderScope(container: container, child: const TerraformationApp()));
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No se pudo iniciar la aplicación: $e'))),
      ),
    ));
  }
}
