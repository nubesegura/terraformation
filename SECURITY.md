# Security policy

If you find a vulnerability, **do not open a public issue**. Use the
*Report a vulnerability* feature of GitHub (Security → Advisories) on the
repository, stating the version, reproduction steps and impact.

Relevant design principles: least privilege in IAM, the raw state is never
stored in DynamoDB, sensitive attributes are masked at ingestion and
the API requires an Amazon Cognito JWT.
