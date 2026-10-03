#!/usr/bin/env bash
# Activación MANUAL de EventBridge en el bucket de states (alternativa al custom resource,
# ManageBucketNotifications=false). Conserva la configuración de notificaciones existente.
#
#   scripts/enable-eventbridge.sh <bucket> [--apply] [--profile P]
#
# Sin --apply solo muestra la configuración que se enviaría (dry-run).
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
echo "Configuración actual:"; echo "$CURRENT" | jq .

# PutBucketNotificationConfiguration REEMPLAZA todo: se conserva lo existente y se agrega EventBridge.
NEW="$(echo "$CURRENT" | jq '. + {EventBridgeConfiguration: {}}')"
echo "Configuración a aplicar:"; echo "$NEW" | jq .

if [ "$APPLY" -eq 1 ]; then
  aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
    --notification-configuration "$NEW" "${PROFILE_ARGS[@]}"
  echo "EventBridge habilitado en s3://$BUCKET"
else
  echo "(dry-run) añade --apply para aplicar"
fi
