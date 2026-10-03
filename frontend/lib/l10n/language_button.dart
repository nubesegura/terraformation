import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_strings.dart';
import 'lang_provider.dart';

/// Language selector (English / Español). Shows the current language and opens a menu to switch.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    return PopupMenuButton<AppLang>(
      tooltip: context.s.tipLanguage,
      initialValue: lang,
      onSelected: ref.read(langProvider.notifier).set,
      itemBuilder: (_) => [
        for (final l in AppLang.values)
          CheckedPopupMenuItem(value: l, checked: l == lang, child: Text('${l.short} · ${l.nativeName}')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.translate, size: 20),
          const SizedBox(width: 4),
          Text(lang.short, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
