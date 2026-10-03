#!/usr/bin/env bash
# Creates (if missing) the `cloudformation package` artifacts bucket, with the standard's
# security controls: block public access, versioning, SSE-KMS (aws/s3) + Bucket Key, ACLs
# disabled, mandatory TLS, lifecycle and mandatory tags. Idempotent.
#
# Usage: ensure-artifact-bucket.sh <bucket> <region> <env-type> [--profile <perfil>]
set -euo pipefail

BUCKET="${1:?bucket}"; REGION="${2:?region}"; ENV_TYPE="${3:?env-type}"; shift 3
PROFILE_ARGS=("$@")
case "$BUCKET" in *--*) echo "Invalid bucket name ($BUCKET): did aws sts get-caller-identity fail?" >&2; exit 1;; esac
aws_() { aws --region "$REGION" "${PROFILE_ARGS[@]}" "$@"; }

if aws_ s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Artifacts bucket already exists: $BUCKET"
  exit 0
fi

echo "Creating artifacts bucket: $BUCKET ($REGION)"
if [ "$REGION" = "us-east-1" ]; then
  aws_ s3api create-bucket --bucket "$BUCKET" --object-ownership BucketOwnerEnforced >/dev/null
else
  aws_ s3api create-bucket --bucket "$BUCKET" --object-ownership BucketOwnerEnforced \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
fi

aws_ s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws_ s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws_ s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"},"BucketKeyEnabled":true}]}'

NONCURRENT_DAYS=30; [ "$ENV_TYPE" = "prod" ] && NONCURRENT_DAYS=90
aws_ s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration "{
  \"Rules\":[{\"ID\":\"expire-noncurrent-and-abort-multipart\",\"Status\":\"Enabled\",\"Filter\":{},
    \"NoncurrentVersionExpiration\":{\"NoncurrentDays\":$NONCURRENT_DAYS},
    \"AbortIncompleteMultipartUpload\":{\"DaysAfterInitiation\":7}}]}"

aws_ s3api put-bucket-policy --bucket "$BUCKET" --policy "{
  \"Version\":\"2012-10-17\",
  \"Statement\":[{\"Sid\":\"DenyInsecureTransport\",\"Effect\":\"Deny\",\"Principal\":\"*\",
    \"Action\":\"s3:*\",\"Resource\":[\"arn:aws:s3:::$BUCKET\",\"arn:aws:s3:::$BUCKET/*\"],
    \"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}}}]}"

aws_ s3api put-bucket-tagging --bucket "$BUCKET" --tagging "TagSet=[
  {Key=team-owner,Value=nube-segura},{Key=project-name,Value=terraformation},
  {Key=app-name,Value=terraformation},{Key=repo-name,Value=terraformation},
  {Key=env-type,Value=$ENV_TYPE}]"
echo "Artifacts bucket ready: $BUCKET"
