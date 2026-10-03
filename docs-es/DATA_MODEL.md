# Modelo de datos (DynamoDB, tabla única)
> 🇬🇧 English version (primary): [../docs/DATA_MODEL.md](../docs/DATA_MODEL.md)

Claves: `PK`, `SK`. GSI1 (`GSI1PK`,`GSI1SK`), GSI2 (`GSI2PK`,`GSI2SK`), proyección ALL. TTL: atributo `ttl` (planes opcionales).

`SID` = `<proyecto>#<workspace>#<ruta>` (la ruta es relativa al proyecto e incluye el archivo, p. ej. `network/prod.tfstate`).

| Entidad | PK | SK | GSI1 | GSI2 | Atributos principales |
|---|---|---|---|---|---|
| Resumen del state | `PROJECT#SID` | `SUMMARY` | `SUMMARY` / `<last_modified>#SID` | `LOCKED` / `<lock_created>#SID` (solo bloqueado) | project, workspace, path, current_version_id, current_sort, last_modified, serial, lineage, terraform_version, resource_count, by_type, by_provider, by_module, version_count, deleted, lock_state (`locked`/`released`/ausente), lock_* |
| Versión | `PROJECT#SID` | `VERSION#<LastModified ISO>#<versionId>` | – | – | kind (`state`/`delete_marker`), version_id, last_modified, serial, lineage, terraform_version, resource_count, size, s3 {bucket,key,version_id}, added, removed, modified, parse_error |
| Recurso (versión vigente) | `PROJECT#SID` | `RES#<address>` | `RTYPE#<type>` / `SID#<address>` | `RNAME#<name>` / `SID#<address>` | type, name, module, address, provider, mode, index, attrs (map aplanado enmascarado), content_hash, version_sort |
| Lock actual | `PROJECT#SID` | `LOCK#CURRENT` | – | – | status, lock_id, operation, who, version, created, path, version_id, released_at |
| Historial de lock | `PROJECT#SID` | `LOCK#<S3 LastModified>#<versionId>` | – | – | mismos campos + acquired_at, released_at, duration_s |
| Actividad por proyecto | `PROJECT#SID` | `ACT#<yyyy-mm-dd>` | – | – | versions, locks (contadores `ADD`) |
| Actividad global | `ACTIVITY` | `DAY#<yyyy-mm-dd>` | – | – | versions, locks |
| Lineage → state | `LINEAGE#<lineage>` | `STATE#SID` | – | – | project, workspace |
| Plan | `LINEAGE#<lineage>` | `PLAN#<ts>#<uuid>` | – | – | git_remote, git_commit, ci_url, source, terraform_version, resumen de cambios |

## Patrones de acceso

| # | Consulta | Acceso |
|---|---|---|
| A1 | Overview ordenado por última modificación | GSI1 `SUMMARY`, `ScanIndexForward=false` |
| A2 | Detalle/estado de un state | GetItem `SUMMARY` + `LOCK#CURRENT` |
| A3 | Historial de versiones | Query PK, `begins_with(SK,'VERSION#')`, descendente |
| A4 | Locks activos | GSI2 `LOCKED` |
| A5 | Historial de locks | Query PK, `begins_with(SK,'LOCK#2')` (excluye `LOCK#CURRENT`) |
| A6 | Búsqueda por tipo / nombre / proyecto | GSI1 `RTYPE#t` / GSI2 `RNAME#n` / Query PK `RES#` |
| A7 | Actividad | Query `ACTIVITY` rango de días / `ACT#` por proyecto |
| A8 | Versión de un state a una versión dada | Referencia S3 en el ítem `VERSION#` → `GetObject(VersionId)` |
| A9 | Planes de un lineage | Query `LINEAGE#` `begins_with PLAN#` |

## Escrituras e idempotencia

1. Evento → `HeadObject(versionId)` → ¿existe `VERSION#<lm>#<vid>`? sí ⇒ duplicado, se ignora.
2. `GetObject(versionId)` → parse → enmascarado.
3. Conteos de cambios contra la versión anterior (y recálculo del sucesor si llegó fuera de orden).
4. Si es la más reciente por `(LastModified, serial)`: actualización condicional del resumen y sincronización de recursos (solo cambios).
5. Transacción final: `Put VERSION` (`attribute_not_exists`) + `ADD version_count` + `ADD ACT`.
