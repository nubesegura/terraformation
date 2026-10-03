# Terraform → AWS resources map

> 🇪🇸 Versión en español: [docs-es/AWS_MAP.md](../docs-es/AWS_MAP.md)

For **any project** whose `tfstate` is in the bucket, the app shows the **AWS resources** that state deploys, the way
CloudFormation's resources view would. There is no 1-to-1 relation with Terraform elements (an S3 bucket is
`aws_s3_bucket` + versioning + policy + public access block…), so a **versioned map** says which elements make up
each AWS resource.

The Terraform elements view is still available (**Terraform** tab); the **AWS resources** tab is the main one.

## Where it lives

| Piece | Path |
|---|---|
| Map (source of truth) | `backend/src/terraformation/aws_map/resource_map.json` |
| Loader (never raises) | `backend/src/terraformation/aws_map/loader.py` |
| Resolver | `backend/src/terraformation/aws_map/resolver.py` |
| API | `GET /api/projects/{project}/aws-resources` and `GET /api/aws-map/coverage` |
| Verification and proposals | `scripts/check_aws_map.py` (`make aws-map-check`) |

## Map format

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

* **primary**: defines an AWS resource. `cfn_type` is the CloudFormation type; `identity` is the list of candidate
  attributes (the first with a value is used) that identifies it; `name` is for display only.
* **child**: belongs to another resource. `parent.child_attr` is the child's attribute that points to the parent and
  `parent.parent_attr` the parent's attributes it is compared with **by exact value**. A child can hang from another
  child (chain, up to 5 levels; e.g. listener rule → listener → load balancer). `cfn_type` on a child is just the
  label of the equivalent CloudFormation type.
* **status**: `verified` (reviewed and checked with `check_aws_map.py`) or `provisional` (shown with a notice).
* Several Terraform elements with the same identity form **one** AWS resource.

## Fail safe

The map may be outdated or omit types. The rule is to **never guess** (neither by name nor by similarity): every
managed resource ends up in exactly one place and anything doubtful is shown, not hidden.

| Situation | Result in the UI/API |
|---|---|
| The type is not in the map | **Unmapped** · `no_rule` |
| Provider other than AWS | **Unmapped** · `non_aws_provider` |
| The identifier is missing, empty or masked | **Unmapped** · `missing_identity` |
| A child has no link value | **Unmapped** · `missing_parent_ref` |
| The parent is not in the state | **Unmapped** · `orphan_child` |
| The parent matches several resources | **Unmapped** · `ambiguous_parent` |
| A map rule is invalid | **Unmapped** · `invalid_map_entry` (the rest of the map keeps working; `degraded` state) |
| The map file is missing, broken or its version is unsupported | **Everything** unmapped · `map_unavailable` (`unavailable` state, red notice) |
| `reviewed_at` older than `stale_after_days` or invalid | Outdated map notice (it keeps being used) |

Utilities (`random_*`, `time_*`, `null_*`, `tls_*`…) and *data sources* are always listed separately: they do not
create AWS resources, but they are not hidden either. The API never returns an error because of a broken map.

> The `id` of IAM access keys is masked by the parser (it looks like a credential); that is why `aws_iam_access_key`
> is modeled as a child of the IAM user and, if the user is not in the state, stays visible as `orphan_child`.

## Maintaining the map

1. **See what is missing.** `GET /api/aws-map/coverage` checks the current states of all projects and lists the
   unmapped types (with instance count, affected states and reason). Save it to a file.
2. **Propose entries.** `python scripts/check_aws_map.py --coverage coverage.json --propose` suggests a `provisional`
   entry for the `aws_*` types that match a CloudFormation type **exactly**. Proposals are
   **not applied automatically**: review the identity (is it `arn` or `id`?) and whether it is a child resource, and copy them to the map.
3. **Verify.** `make aws-map-check` validates the structure, that parents exist and that there are no cycles, and that each
   `cfn_type` exists in CloudFormation (uses `cfn-lint`). With `--provider-schema schema.json` or `--download-schema`
   (runs `terraform providers schema -json`; downloads the AWS provider, ~700 MB) it also checks that each type and
   attribute exists in the Terraform provider.
4. **Update `reviewed_at`** when you review the map (turns off the outdated notice).
5. Add a test if the entry has an unusual link rule (`backend/tests/test_aws_map.py`).

CI runs the structural and CloudFormation-type verification on every change. The check against the Terraform provider
is manual (heavy); run it when reviewing the map and on provider major version bumps.

## What the map does not do

* It does not query AWS: everything is derived from what is already in the ingested `tfstate` (no new permissions or cost).
* It does not detect *drift* or resources created outside Terraform.
* It does not resolve child resource names to resources of another state (each state is resolved separately).
