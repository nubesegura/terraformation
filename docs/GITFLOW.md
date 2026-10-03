# Gitflow

| Rama | Propósito | Se crea desde | Se integra en |
|---|---|---|---|
| `main` | Producción. Cada merge es desplegable (`prod`). | — | — |
| `develop` | Integración continua (despliega a `dev`). | `main` | `main` (PR) |
| `feature/<tema>` | Trabajo nuevo. | `develop` | `develop` (PR) |

Reglas recomendadas (configúralas en *Settings → Branches*):

* `main` y `develop`: PR obligatorio, CI (`backend`, `infra`, `frontend`) requerido, sin push directo.
* `main`: al menos 1 aprobación.
* Commits con [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `chore:`, `infra:`).

## Environments de GitHub

Crea los environments `dev` (rama `develop`) y `prod` (rama `main`) (*Settings → Environments*). En `prod`, activa
**Required reviewers**. Cada environment lleva:

| Tipo | Nombre | Ejemplo / descripción |
|---|---|---|
| secret | `ROLE_ARN` | Rol IAM asumible por OIDC (GitHub → AWS) con permisos de CloudFormation |
| variable | `AWS_REGION` | Región del bucket de states (el stack debe desplegarse ahí) |
| variable | `STATE_BUCKET` | Bucket S3 existente con los states |
| variable | `ARTIFACT_BUCKET` | (opcional) Bucket de artefactos. Si se omite se deriva del estándar `bckt-<region>-terraformation-artifacts-<cuenta>-<env>` y se crea si no existe |
| variable | `EXTRA_PARAMS` | Parámetros extra, p. ej. `EnablePlansApi=true` |

Comandos (`gh` CLI, ejecútalos tú):

```bash
gh api -X PUT repos/<owner>/<repo>/environments/dev
gh api -X PUT repos/<owner>/<repo>/environments/prod
gh secret set ROLE_ARN --env dev  --body "arn:aws:iam::<cuenta>:role/<rol-github-oidc>"
gh variable set AWS_REGION     --env dev --body "us-east-1"
gh variable set STATE_BUCKET   --env dev --body "<bucket-de-states>"
```
