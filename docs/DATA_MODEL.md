# Data model (DynamoDB, single table)

> 🇪🇸 Versión en español: [docs-es/DATA_MODEL.md](../docs-es/DATA_MODEL.md)

Keys: `PK`, `SK`. GSI1 (`GSI1PK`,`GSI1SK`), GSI2 (`GSI2PK`,`GSI2SK`), ALL projection. TTL: attribute `ttl` (optional plans).

`SID` = `<project>#<workspace>#<path>` (the path is relative to the project and includes the file, e.g. `network/prod.tfstate`).

| Entity | PK | SK | GSI1 | GSI2 | Main attributes |
|---|---|---|---|---|---|
| State summary | `PROJECT#SID` | `SUMMARY` | `SUMMARY` / `<last_modified>#SID` | `LOCKED` / `<lock_created>#SID` (locked only) | project, workspace, path, current_version_id, current_sort, last_modified, serial, lineage, terraform_version, resource_count, by_type, by_provider, by_module, version_count, deleted, lock_state (`locked`/`released`/absent), lock_* |
| Version | `PROJECT#SID` | `VERSION#<LastModified ISO>#<versionId>` | – | – | kind (`state`/`delete_marker`), version_id, last_modified, serial, lineage, terraform_version, resource_count, size, s3 {bucket,key,version_id}, added, removed, modified, parse_error |
| Resource (current version) | `PROJECT#SID` | `RES#<address>` | `RTYPE#<type>` / `SID#<address>` | `RNAME#<name>` / `SID#<address>` | type, name, module, address, provider, mode, index, attrs (flattened, masked map), content_hash, version_sort |
| Current lock | `PROJECT#SID` | `LOCK#CURRENT` | – | – | status, lock_id, operation, who, version, created, path, version_id, released_at |
| Lock history | `PROJECT#SID` | `LOCK#<S3 LastModified>#<versionId>` | – | – | same fields + acquired_at, released_at, duration_s |
| Per-project activity | `PROJECT#SID` | `ACT#<yyyy-mm-dd>` | – | – | versions, locks (`ADD` counters) |
| Global activity | `ACTIVITY` | `DAY#<yyyy-mm-dd>` | – | – | versions, locks |
| Lineage → state | `LINEAGE#<lineage>` | `STATE#SID` | – | – | project, workspace |
| Plan | `LINEAGE#<lineage>` | `PLAN#<ts>#<uuid>` | – | – | git_remote, git_commit, ci_url, source, terraform_version, change summary |

## Access patterns

| # | Query | Access |
|---|---|---|
| A1 | Overview ordered by last modification | GSI1 `SUMMARY`, `ScanIndexForward=false` |
| A2 | Detail/status of a state | GetItem `SUMMARY` + `LOCK#CURRENT` |
| A3 | Version history | Query PK, `begins_with(SK,'VERSION#')`, descending |
| A4 | Active locks | GSI2 `LOCKED` |
| A5 | Lock history | Query PK, `begins_with(SK,'LOCK#2')` (excludes `LOCK#CURRENT`) |
| A6 | Search by type / name / project | GSI1 `RTYPE#t` / GSI2 `RNAME#n` / Query PK `RES#` |
| A7 | Activity | Query `ACTIVITY` day range / `ACT#` per project |
| A8 | A state at a given version | S3 reference in the `VERSION#` item → `GetObject(VersionId)` |
| A9 | Plans of a lineage | Query `LINEAGE#` `begins_with PLAN#` |

## Writes and idempotency

1. Event → `HeadObject(versionId)` → does `VERSION#<lm>#<vid>` exist? yes ⇒ duplicate, ignored.
2. `GetObject(versionId)` → parse → masking.
3. Change counts against the previous version (and recalculation of the successor if it arrived out of order).
4. If it is the newest by `(LastModified, serial)`: conditional update of the summary and resource sync (changes only).
5. Final transaction: `Put VERSION` (`attribute_not_exists`) + `ADD version_count` + `ADD ACT`.
