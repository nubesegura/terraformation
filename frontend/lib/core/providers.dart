import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/models.dart';
import 'state_ref.dart';

final dashboardProvider = FutureProvider.autoDispose<DashboardData>(
  (ref) => ref.watch(apiClientProvider).dashboard(),
);

final projectsQueryProvider = NotifierProvider<_QueryNotifier, String>(_QueryNotifier.new);

class _QueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final projectsProvider = FutureProvider.autoDispose<ProjectList>((ref) {
  final q = ref.watch(projectsQueryProvider);
  return ref.watch(apiClientProvider).projects(q: q);
});

final projectProvider = FutureProvider.autoDispose.family<Project, StateRef>(
  (ref, k) => ref.watch(apiClientProvider).project(k),
);

final versionsProvider = FutureProvider.autoDispose.family<VersionList, StateRef>(
  (ref, k) => ref.watch(apiClientProvider).versions(k),
);

final timelineProvider = FutureProvider.autoDispose.family<Timeline, StateRef>(
  (ref, k) => ref.watch(apiClientProvider).timeline(k),
);

final stateDetailProvider = FutureProvider.autoDispose.family<StateDetail, (StateRef, String)>(
  (ref, k) => ref.watch(apiClientProvider).state(k.$1, k.$2),
);

final graphProvider = FutureProvider.autoDispose.family<DependencyGraph, (StateRef, String)>(
  (ref, k) => ref.watch(apiClientProvider).graph(k.$1, k.$2),
);

final diffProvider = FutureProvider.autoDispose.family<StateDiff, (StateRef, String, String)>(
  (ref, k) => ref.watch(apiClientProvider).diff(k.$1, k.$2, k.$3),
);

final awsResourcesProvider = FutureProvider.autoDispose.family<AwsResources, StateRef>(
  (ref, k) => ref.watch(apiClientProvider).awsResources(k),
);

final projectLocksProvider = FutureProvider.autoDispose.family<LockHistory, StateRef>(
  (ref, k) => ref.watch(apiClientProvider).projectLocks(k),
);

final activeLocksProvider = FutureProvider.autoDispose<ActiveLocks>(
  (ref) => ref.watch(apiClientProvider).activeLocks(),
);

final facetsProvider = FutureProvider.autoDispose<Facets>(
  (ref) => ref.watch(apiClientProvider).facets(),
);
