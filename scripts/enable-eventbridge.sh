#!/usr/bin/env bash
# MANUAL activation of EventBridge on the states bucket (alternative to the custom resource,
# ManageBucketNotifications=false). Preserves the existing notification configuration.
#
#   scripts/enable-eventbridge.sh <bucket> [--apply] [--profile P]
#
# Without --apply it only shows the configuration that would be sent (dry-run).
set -euo pipefail

BUCKET="${1:?uso: $0 <bucket> [--apply] [--profile P]}"
shift || true
APPLY=0
PROFILE_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --profile) PROFILE_ARGS=(--profile "$2"); shift ;;
    *) echo "argumento desconocido: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null || { echo "se requiere jq" >&2; exit 1; }

CURRENT="$(aws s3api get-bucket-notification-configuration --bucket "$BUCKET" "${PROFILE_ARGS[@]}" --output json)"
echo "Current configuration:"; echo "$CURRENT" | jq .

# PutBucketNotificationConfiguration REPLACES everything: the existing config is kept and EventBridge is added.
NEW="$(echo "$CURRENT" | jq '. + {EventBridgeConfiguration: {}}')"
echo "Configuration to apply:"; echo "$NEW" | jq .

if [ "$APPLY" -eq 1 ]; then
  aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
    --notification-configuration "$NEW" "${PROFILE_ARGS[@]}"
  echo "EventBridge habilitado en s3://$BUCKET"
else
  echo "(dry-run) add --apply to apply"
fi
