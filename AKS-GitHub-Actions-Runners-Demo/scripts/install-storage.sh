#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ $# == 0 ]] || fail "Usage: bash scripts/install-storage.sh"
require_tools terraform kubectl
[[ -f "$KUBECONFIG" ]] || fail "Connect to this demo cluster before installing storage."
storage_account="$(tf_output storage_account_name)"
resource_group="$(tf_output resource_group_name)"
subscription="$(tf_output subscription_id)"
cache_share="$(tf_output cache_share_name)"
cache_quota="$(tf_output cache_share_quota_gib)"

# The PV is Retain: if the nuget-cache PVC was deleted, the PV stays Released and pinned
# to the old claim UID. Clear it so the recreated PVC can bind (share data is kept).
cache_pv_phase="$(kubectl get pv arc-nuget-cache --ignore-not-found -o jsonpath='{.status.phase}')"
if [[ "$cache_pv_phase" == "Released" ]]; then
  kubectl patch pv arc-nuget-cache --type=merge \
    -p '{"spec":{"claimRef":{"uid":null,"resourceVersion":null}}}'
fi

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: arc-nuget-cache
spec:
  capacity:
    storage: ${cache_quota}Gi
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  claimRef:
    namespace: arc-runners
    name: nuget-cache
  mountOptions:
    - dir_mode=0770
    - file_mode=0660
    - uid=1001
    - gid=123
    - mfsymlinks
    - cache=strict
    - nosharesock
    - actimeo=30
  csi:
    driver: file.csi.azure.com
    volumeHandle: "${resource_group}#${storage_account}#${cache_share}###arc-runners#${subscription}"
    volumeAttributes:
      resourceGroup: "$resource_group"
      storageAccount: "$storage_account"
      shareName: "$cache_share"
      subscriptionID: "$subscription"
      protocol: smb
      storeAccountKey: "false"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nuget-cache
  namespace: arc-runners
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ""
  volumeName: arc-nuget-cache
  resources:
    requests:
      storage: ${cache_quota}Gi
EOF
kubectl wait --namespace "$RUNNER_NAMESPACE" pvc/nuget-cache \
  --for=jsonpath='{.status.phase}'=Bound --timeout=120s
# Earlier versions put runner workspaces on this Azure Files class; it is no longer used.
kubectl delete storageclass arc-azurefile-premium --ignore-not-found
echo "Azure Files NuGet cache bound; runner workspaces use per-runner managed disks."
