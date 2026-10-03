# Terraformation Web (Flutter)

Frontend de Terraformation (web). Estructura por *features* con Riverpod, `go_router`, cliente HTTP
tipado (`lib/core/api`) alineado con `docs/openapi.yaml` (se verifica con
`python scripts/check_dart_models.py`).

```bash
flutter pub get
flutter analyze && flutter test
flutter build web --release --no-web-resources-cdn   # recursos locales (compatible con la CSP)
```

La app lee `config.json` en tiempo de ejecución (ver `make web-config` en la raíz). Para desarrollo
local con la API simulada: `python scripts/e2e_smoke.py --shots /tmp/shots` desde la raíz.
