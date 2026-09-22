#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

read -r -p "This will destroy the Harbor production demo resources in Azure. Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Captured before destroy - terraform outputs are gone once state is empty.
CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw cluster_name 2>/dev/null || true)"
RESOURCE_GROUP="$(terraform -chdir="$TF_DIR" output -raw resource_group_name 2>/dev/null || true)"

if [[ -d "$TF_DIR" ]]; then
  # Azure eventual consistency (e.g. RG-delete or NIC/NSG detach lag) can make
  # a single destroy pass fail transiently; retry a few times before giving up.
  destroy_attempts=3
  for attempt in $(seq 1 "$destroy_attempts"); do
    if terraform -chdir="$TF_DIR" destroy -auto-approve; then
      break
    fi
    if [[ "$attempt" -lt "$destroy_attempts" ]]; then
      echo "terraform destroy failed (attempt $attempt/$destroy_attempts) - likely Azure eventual consistency. Retrying in 30s..."
      sleep 30
    else
      echo "terraform destroy did not complete after $destroy_attempts attempts. Re-run ./cleanup.sh to retry, or check the Azure portal for leftover resources."
    fi
  done
fi

# Helm/kubectl cleanup is unnecessary: the AKS API server is private, and
# terraform destroy above already removes the cluster (and everything on it).
rm -rf "$SCRIPT_DIR/.rendered"

if [[ -n "$CLUSTER_NAME" ]] && command -v kubectl >/dev/null 2>&1 && kubectl config get-contexts "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "Removing local kubectl config entries for $CLUSTER_NAME..."
  kubectl config delete-context "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kubectl config delete-cluster "$CLUSTER_NAME" >/dev/null 2>&1 || true
  kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" >/dev/null 2>&1 || true
  kubectl config delete-user "clusterAdmin_${RESOURCE_GROUP}_${CLUSTER_NAME}" >/dev/null 2>&1 || true
fi

echo "Cleanup completed."
