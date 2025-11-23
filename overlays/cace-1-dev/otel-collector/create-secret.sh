#!/usr/bin/env bash
set -euo pipefail

# Usage: ./create-secret.sh path/to/private-key.pem <app-id> <installation-id> <webhook-secret> [namespace]
keyfile=${1:-}
app_id=${2:-}
install_id=${3:-}
webhook_secret=${4:-}
ns=${5:-observability}

if [[ -z "$keyfile" || -z "$app_id" || -z "$install_id" || -z "$webhook_secret" ]]; then
  echo "Usage: $0 /home/fmsimard/.pem <app-id> <installation-id> <webhook-secret> [namespace]"
  exit 2
fi

kubectl -n "$ns" create secret generic github-app-secret \
  --from-file=github_private_key_pem="$keyfile" \
  --from-literal=github_app_id="$app_id" \
  --from-literal=github_installation_id="$install_id" \
  --from-literal=github_webhook_secret="$webhook_secret" -o yaml --dry-run=client | kubectl apply -f -

echo "Secret 'github-app-secret' created/updated in namespace ${ns}."
