# PROGRESS

Estado: **todas las fases completadas** (ver commits convencionales por fase).

## Fases
- [x] 1 Estructura del repo, `docs/DECISIONS.md`, modelo de datos (`docs/DATA_MODEL.md`) y contrato OpenAPI (generado por FastAPI en la fase 4)
- [x] 2 Parser v4, enmascarado, diff y grafo con pruebas
- [x] 3 Lambdas de ingesta, locks, backfill y reconciliación (pruebas con moto)
- [x] 4 API FastAPI (Mangum) + planes opcionales + OpenAPI; authorizer = JWT nativo de HTTP API
- [x] 5 Plantillas CloudFormation/SAM (cfn-lint, checkov, cfn-guard sin hallazgos)
- [x] 6 Frontend Flutter (analyze, test, build web, e2e con Chromium)
- [x] 7 README, Makefile, CI/CD, gitflow, pulido final

## Verificación local (última ejecución)
- `ruff`, `mypy --strict`, `pytest` (moto): ver `make check`
- `cfn-lint`, `checkov` (0 fallos), `cfn-guard` (sin fallos)
- `flutter analyze`, `flutter test`, `flutter build web --no-web-resources-cdn`
- `python scripts/e2e_smoke.py`: FastAPI + moto + build de Flutter en Chromium, sin errores de consola

## Pendiente (acciones del usuario, no automatizables desde la sesión)
- Crear environments/variables/secrets de GitHub y reglas de protección de ramas (ver `docs/GITFLOW.md`)
- Desplegar con `make deploy` y ejecutar `make backfill` (no se desplegó nada en AWS)
- Aplicar las reglas de lifecycle de `.tflock` si se desea (`make lifecycle-rules`)

## Problemas encontrados y resueltos
- Requisito añadido en curso: Python + Pydantic + FastAPI (D1).
- `cfn-lint --ignore-checks X archivos` consume los archivos como valores de la opción: se pasan los archivos primero.
- `S3 Lifecycle` no filtra por sufijo → se usa la key exacta del lock como prefijo (D32).
- La expiración de versiones de `.tflock` genera `Object Deleted (Permanently Deleted)`: no debe liberar locks (D14).
- El cliente `table.meta.client` de boto3 ya serializa valores: no usar `TypeSerializer` en `transact_write_items`.
- Palabras reservadas de DynamoDB (`project`, `workspace`...): `build_update` alias todos los nombres.
