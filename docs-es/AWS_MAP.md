# Mapa Terraform → recursos AWS
> 🇬🇧 English version (primary): [../docs/AWS_MAP.md](../docs/AWS_MAP.md)

La app muestra, para **cualquier proyecto** cuyo `tfstate` esté en el bucket, los **recursos AWS** que ese state
despliega, como lo haría la vista de recursos de CloudFormation. No hay una relación 1 a 1 con los elementos de
Terraform (un bucket S3 son `aws_s3_bucket` + versionado + política + bloqueo de acceso público…), así que un
**mapa versionado** indica qué elementos forman cada recurso AWS.

La vista de elementos de Terraform sigue disponible (pestaña **Terraform**); la pestaña **Recursos AWS** es la principal.

## Dónde vive

| Pieza | Ruta |
|---|---|
| Mapa (fuente de verdad) | `backend/src/terraformation/aws_map/resource_map.json` |
| Cargador (nunca lanza) | `backend/src/terraformation/aws_map/loader.py` |
| Resolvedor | `backend/src/terraformation/aws_map/resolver.py` |
| API | `GET /api/projects/{project}/aws-resources` y `GET /api/aws-map/coverage` |
| Verificación y propuestas | `scripts/check_aws_map.py` (`make aws-map-check`) |

## Formato del mapa

```json
{
  "schema_version": 1,
  "reviewed_at": "2026-10-03",
  "stale_after_days": 180,
  "entries": {
    "aws_s3_bucket": {
      "role": "primary", "cfn_type": "AWS::S3::Bucket",
      "identity": ["id"], "name": ["bucket"], "status": "verified"
    },
    "aws_s3_bucket_policy": {
      "role": "child", "cfn_type": "AWS::S3::BucketPolicy", "status": "verified",
      "parent": {"type": "aws_s3_bucket", "child_attr": "bucket", "parent_attr": ["id", "bucket"]}
    }
  }
}
```

* **primary**: define un recurso AWS. `cfn_type` es el tipo de CloudFormation; `identity` es la lista de atributos
  candidatos (se usa el primero con valor) que lo identifica; `name` es solo para mostrar.
* **child**: pertenece a otro recurso. `parent.child_attr` es el atributo del hijo que apunta al padre y
  `parent.parent_attr` los atributos del padre con los que se compara **por valor exacto**. Un hijo puede colgar de otro
  hijo (cadena, hasta 5 niveles; p. ej. regla de listener → listener → balanceador). `cfn_type` en un hijo es solo la
  etiqueta del tipo de CloudFormation equivalente.
* **status**: `verified` (revisada y comprobada con `check_aws_map.py`) o `provisional` (se muestra con un aviso).
* Varios elementos de Terraform con la misma identidad forman **un solo** recurso AWS.

## Falla segura

El mapa puede estar desactualizado u omitir tipos. La regla es **no adivinar jamás** (ni por nombre ni por parecido):
todo recurso gestionado queda en exactamente un lugar y lo dudoso se muestra, no se oculta.

| Situación | Resultado en la UI/API |
|---|---|
| El tipo no está en el mapa | **Sin mapear** · `no_rule` |
| Proveedor distinto de AWS | **Sin mapear** · `non_aws_provider` |
| El identificador falta, está vacío o enmascarado | **Sin mapear** · `missing_identity` |
| Un hijo no tiene valor de enlace | **Sin mapear** · `missing_parent_ref` |
| El padre no está en el state | **Sin mapear** · `orphan_child` |
| El padre coincide con varios recursos | **Sin mapear** · `ambiguous_parent` |
| Una regla del mapa es inválida | **Sin mapear** · `invalid_map_entry` (el resto del mapa sigue funcionando; estado `degraded`) |
| El archivo del mapa falta, está roto o su versión no se soporta | **Todo** sin mapear · `map_unavailable` (estado `unavailable`, aviso rojo) |
| `reviewed_at` más antiguo que `stale_after_days` o inválido | Aviso de mapa desactualizado (se sigue usando) |

Siempre se listan aparte las utilidades (`random_*`, `time_*`, `null_*`, `tls_*`…) y los *data sources*: no crean
recursos AWS, pero tampoco se esconden. La API nunca devuelve error por un mapa roto.

> El `id` de las claves de acceso IAM lo enmascara el parser (parece una credencial); por eso `aws_iam_access_key` se
> modela como hijo del usuario IAM y, si el usuario no está en el state, queda visible como `orphan_child`.

## Mantener el mapa

1. **Ver qué falta.** `GET /api/aws-map/coverage` revisa los states vigentes de todos los proyectos y lista los
   tipos sin mapear (con número de instancias, states afectados y motivo). Guárdalo en un archivo.
2. **Proponer entradas.** `python scripts/check_aws_map.py --coverage cobertura.json --propose` sugiere, para los
   tipos `aws_*` que coinciden **exactamente** con un tipo de CloudFormation, una entrada `provisional`. Las propuestas
   **no se aplican solas**: revisa la identidad (¿es `arn` o `id`?) y si es un recurso hijo, y cópialas al mapa.
3. **Verificar.** `make aws-map-check` valida la estructura, que los padres existan y que no haya ciclos, y que cada
   `cfn_type` exista en CloudFormation (usa `cfn-lint`). Con `--provider-schema esquema.json` o `--download-schema`
   (ejecuta `terraform providers schema -json`; descarga el proveedor AWS, ~700 MB) comprueba además que cada tipo y
   atributo exista en el proveedor de Terraform.
4. **Actualizar `reviewed_at`** al revisar el mapa (apaga el aviso de desactualizado).
5. Añade un test si la entrada tiene una regla de enlace poco habitual (`backend/tests/test_aws_map.py`).

El CI ejecuta la verificación estructural y de tipos de CloudFormation en cada cambio. La comprobación contra el proveedor de
Terraform es manual (pesada); se recomienda correrla al revisar el mapa y al subir de versión mayor del proveedor.

## Lo que el mapa no hace

* No consulta AWS: deriva todo de lo que ya está en el `tfstate` ingerido (sin permisos nuevos ni costo).
* No detecta *drift* ni recursos creados fuera de Terraform.
* No resuelve nombres de recursos hijos a recursos de otro state (cada state se resuelve por separado).
