# Gitflow

> 🇪🇸 Versión en español: [docs-es/GITFLOW.md](../docs-es/GITFLOW.md)

| Branch | Purpose | Created from | Merged into |
|---|---|---|---|
| `main` | Production. Every merge is deployable (`prod`). | — | — |
| `develop` | Continuous integration (deploys to `dev`). | `main` | `main` (PR) |
| `feature/<topic>` | New work. | `develop` | `develop` (PR) |

Recommended rules (configure them in *Settings → Branches*):

* `main` and `develop`: PR required, CI (`backend`, `infra`, `frontend`) required, no direct pushes.
* `main`: at least 1 approval.
* Commits follow [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `chore:`, `infra:`).

## GitHub environments

Create the `dev` (branch `develop`) and `prod` (branch `main`) environments (*Settings → Environments*). On `prod`, enable
**Required reviewers**. Each environment holds:

| Type | Name | Example / description |
|---|---|---|
| secret | `ROLE_ARN` | IAM role assumable through OIDC (GitHub → AWS) with CloudFormation permissions |
| variable | `AWS_REGION` | Region of the states bucket (the stack must be deployed there) |
| variable | `STATE_BUCKET` | Existing S3 bucket that holds the states |
| variable | `ARTIFACT_BUCKET` | (optional) Artifacts bucket. If omitted it is derived from the standard `bckt-<region>-terraformation-artifacts-<account>-<env>` and created if missing |
| variable | `EXTRA_PARAMS` | Extra parameters, e.g. `EnablePlansApi=true` |

Commands (`gh` CLI, run them yourself):

```bash
gh api -X PUT repos/<owner>/<repo>/environments/dev
gh api -X PUT repos/<owner>/<repo>/environments/prod
gh secret set ROLE_ARN --env dev  --body "arn:aws:iam::<account>:role/<github-oidc-role>"
gh variable set AWS_REGION     --env dev --body "us-east-1"
gh variable set STATE_BUCKET   --env dev --body "<states-bucket>"
```
