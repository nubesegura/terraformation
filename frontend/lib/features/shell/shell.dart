import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth.dart';
import '../../core/providers.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void toggle(Brightness current) =>
      state = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

const _destinations = [
  (path: '/', label: 'Dashboard', icon: Icons.space_dashboard_outlined),
  (path: '/projects', label: 'Proyectos', icon: Icons.folder_copy_outlined),
  (path: '/search', label: 'Búsqueda', icon: Icons.manage_search),
  (path: '/locks', label: 'Locks', icon: Icons.lock_clock),
];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  int get _index {
    if (location == '/') return 0;
    final i = _destinations.indexWhere((d) => d.path != '/' && location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final auth = ref.watch(authProvider);
    final locks = ref.watch(activeLocksProvider).asData?.value;
    final alerts = locks?.items.where((l) => l.alert).length ?? 0;
    final brightness = Theme.of(context).brightness;

    final actions = <Widget>[
      if (alerts > 0)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Badge.count(
            count: alerts,
            child: IconButton(
              tooltip: 'Locks con alerta',
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              onPressed: () => context.go('/locks'),
            ),
          ),
        ),
      IconButton(
        tooltip: 'Cambiar tema',
        icon: Icon(brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
        onPressed: () => ref.read(themeModeProvider.notifier).toggle(brightness),
      ),
      IconButton(
        tooltip: 'Actualizar',
        icon: const Icon(Icons.refresh),
        onPressed: () {
          ref.invalidate(dashboardProvider);
          ref.invalidate(projectsProvider);
          ref.invalidate(activeLocksProvider);
        },
      ),
      PopupMenuButton<String>(
        tooltip: auth.email ?? 'Cuenta',
        icon: const Icon(Icons.account_circle_outlined),
        onSelected: (v) {
          if (v == 'logout') ref.read(authProvider.notifier).logout();
        },
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text(auth.email ?? 'Sesión activa')),
          const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
        ],
      ),
      const SizedBox(width: 8),
    ];

    final title = Row(children: [
      Icon(Icons.layers, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      const Text('Terraformation', style: TextStyle(fontWeight: FontWeight.w700)),
    ]);

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: title, actions: actions),
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: [
          for (final d in _destinations) NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
