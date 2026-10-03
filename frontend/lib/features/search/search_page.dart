import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/state_ref.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../../l10n/app_strings.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _name = TextEditingController();
  final _module = TextEditingController();
  final _attrKey = TextEditingController();
  final _attrValue = TextEditingController();
  String? _type;
  String? _project;
  AsyncValue<SearchResult>? _result;

  Future<void> _run() async {
    if ([_type, _name.text, _module.text, _project, _attrKey.text, _attrValue.text]
        .every((e) => e == null || e.isEmpty)) {
      setState(() => _result = AsyncValue.error(context.s.searchNeedFilter, StackTrace.current));
      return;
    }
    setState(() => _result = const AsyncValue.loading());
    try {
      final r = await ref.read(apiClientProvider).search(
            type: _type,
            name: _name.text.trim(),
            module: _module.text.trim(),
            project: _project,
            attributeKey: _attrKey.text.trim(),
            attributeValue: _attrValue.text.trim(),
          );
      setState(() => _result = AsyncValue.data(r));
    } catch (e, st) {
      setState(() => _result = AsyncValue.error(e, st));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _module, _attrKey, _attrValue]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final facets = ref.watch(facetsProvider).asData?.value;
    Widget field(String label, TextEditingController c, {double w = 210}) => SizedBox(
          width: w,
          child: TextField(
            controller: c,
            decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
            onSubmitted: (_) => _run(),
          ),
        );
    return SingleChildScrollView(
      child: PageBody(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.s.searchTitle, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(context.s.searchSubtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 260,
                  child: Autocomplete<String>(
                    optionsBuilder: (v) => (facets?.resourceTypes.keys ?? const <String>[])
                        .where((t) => t.contains(v.text.toLowerCase())),
                    onSelected: (v) => _type = v,
                    fieldViewBuilder: (context, c, f, _) => TextField(
                      controller: c,
                      focusNode: f,
                      decoration: InputDecoration(labelText: context.s.typeLabel, isDense: true, border: const OutlineInputBorder()),
                      onChanged: (v) => _type = v.trim().isEmpty ? null : v.trim(),
                      onSubmitted: (_) => _run(),
                    ),
                  ),
                ),
                field(context.s.nameLabel, _name),
                field(context.s.moduleLabel, _module),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _project,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.s.projectLabel, isDense: true, border: const OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: null, child: Text(context.s.allLabel)),
                      for (final p in facets?.projects ?? const <String>[]) DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (v) => _project = v,
                  ),
                ),
                field(context.s.attrKeyLabel, _attrKey),
                field(context.s.attrValueLabel, _attrValue),
                FilledButton.icon(onPressed: _run, icon: const Icon(Icons.search), label: Text(context.s.searchButton)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (_result != null)
            AsyncView<SearchResult>(
              value: _result!,
              onRetry: _run,
              builder: (r) => r.items.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(context.s.noResults))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.cursor != null ? context.s.resultsCountMore(r.items.length) : context.s.resultsCount(r.items.length)),
                      const SizedBox(height: 8),
                      for (final h in r.items) _HitTile(h: h),
                    ]),
            ),
        ]),
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.h});
  final SearchHit h;
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.go(stateLocation(h.stateRef, extra: {'tab': 'state'})),
        title: Text(h.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Tag(stateLabel(h.stateRef), icon: Icons.folder_outlined, color: Palette.of(0)),
            Tag(h.type),
            Tag(h.module),
            if (h.provider.isNotEmpty) Tag(h.provider),
          ]),
          if (h.attributes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(h.attributes.entries.map((e) => '${e.key} = ${e.value}').join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
            ),
        ]),
      ),
    );
  }
}
