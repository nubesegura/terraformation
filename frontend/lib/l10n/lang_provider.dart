import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth.dart';
import 'app_strings.dart';

const kLangStorageKey = 'tf.lang';

/// Selected UI language. English is the default; the choice is remembered in the browser (localStorage).
class LangNotifier extends Notifier<AppLang> {
  @override
  AppLang build() {
    final browser = ref.read(browserProvider);
    final lang = AppLang.fromCode(browser.getLocal(kLangStorageKey));
    browser.setDocumentLang(lang.name);
    return lang;
  }

  void set(AppLang lang) {
    if (lang == state) return;
    final browser = ref.read(browserProvider);
    browser.setLocal(kLangStorageKey, lang.name);
    browser.setDocumentLang(lang.name);
    state = lang;
  }
}

final langProvider = NotifierProvider<LangNotifier, AppLang>(LangNotifier.new);

final stringsProvider = Provider<AppStrings>((ref) => AppStrings(ref.watch(langProvider)));
