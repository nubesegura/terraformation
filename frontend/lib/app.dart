import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth.dart';
import 'core/state_ref.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/diff/diff_page.dart';
import 'features/locks/locks_page.dart';
import 'features/projects/project_page.dart';
import 'features/projects/projects_page.dart';
import 'features/search/search_page.dart';
import 'features/shell/shell.dart';
import 'shared/theme.dart';

StateRef _stateRef(GoRouterState s) => (
      project: s.pathParameters['project']!,
      workspace: s.uri.queryParameters['workspace'] ?? 'default',
      path: s.uri.queryParameters['path'] ?? defaultStatePath,
    );

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loggingIn = state.matchedLocation == '/login';
      if (auth.busy) return null;
      if (!auth.authenticated) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/projects', builder: (_, _) => const ProjectsPage()),
          GoRoute(
            path: '/projects/:project',
            builder: (_, s) => ProjectPage(
              stateRef: _stateRef(s),
              tab: s.uri.queryParameters['tab'],
              version: s.uri.queryParameters['version'],
            ),
            routes: [
              GoRoute(
                path: 'diff',
                builder: (_, s) => DiffPage(
                  stateRef: _stateRef(s),
                  from: s.uri.queryParameters['from'],
                  to: s.uri.queryParameters['to'],
                ),
              ),
            ],
          ),
          GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
          GoRoute(path: '/locks', builder: (_, _) => const LocksPage()),
        ],
      ),
    ],
  );
});

class TerraformationApp extends ConsumerWidget {
  const TerraformationApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Terraformation',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.layers, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('Terraformation', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                const Text('Visor de Terraform states en S3', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton.icon(
                  onPressed: auth.busy ? null : () => ref.read(authProvider.notifier).login(),
                  icon: const Icon(Icons.login),
                  label: const Text('Iniciar sesión'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
