# Terraformation Web (Flutter)

> 🇪🇸 Versión en español: [docs-es/FRONTEND.md](../docs-es/FRONTEND.md)

Terraformation frontend (web). Feature-based structure with Riverpod, `go_router`, and a typed HTTP client
(`lib/core/api`) aligned with `docs/openapi.yaml` (checked with
`python scripts/check_dart_models.py`).

```bash
flutter pub get
flutter analyze && flutter test
flutter build web --release --no-web-resources-cdn   # local resources (CSP compatible)
```

The app reads `config.json` at runtime (see `make web-config` at the repo root). For local development
with the simulated API: `python scripts/e2e_smoke.py --shots /tmp/shots` from the repo root.

## Languages

English is the default language. The language button in the app bar (EN / ES) switches the whole UI at
runtime; the choice is stored in `localStorage` (`tf.lang`) and updates `<html lang>`. Strings live in
`lib/l10n/app_strings.dart` as side-by-side `_('English', 'Español')` pairs, so a missing translation is a
compile error. To add a language, add a value to `AppLang` and a third argument per string.
