#!/bin/bash
# Terraform `external` data source helper: prints {"revision": "asm-X-Y"} for
# the newest Istio add-on revision compatible with the given AKS Kubernetes
# version in the given region. Used only when var.istio_revisions is empty -
# the service_mesh_profile.revisions attribute requires at least one entry,
# it is not actually optional despite what the provider docs imply.
set -euo pipefail

LOCATION="$1"
KUBERNETES_VERSION="$2"

REVISION=$(az aks mesh get-revisions --location "$LOCATION" -o json --only-show-errors | jq -r --arg kv "$KUBERNETES_VERSION" '
  [.meshRevisions[] | select([.compatibleWith[].versions[]] | index($kv))]
  | sort_by(.revision | ltrimstr("asm-1-") | tonumber)
  | last.revision // empty
')

if [ -z "$REVISION" ]; then
  echo "No Istio add-on revision compatible with Kubernetes ${KUBERNETES_VERSION} found in ${LOCATION}. Run: az aks mesh get-revisions --location ${LOCATION} -o table" >&2
  exit 1
fi

jq -n --arg revision "$REVISION" '{revision: $revision}'
