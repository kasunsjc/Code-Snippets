#!/bin/bash
# Post-Terraform helper commands for the AKS Argo CD extension demo.
#
# Run `terraform apply` in ./terraform first. Then export the outputs and
# execute the steps below to finish wiring DNS + verify the deployment.

set -euo pipefail

pushd "$(dirname "$0")/terraform" >/dev/null

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
KEY_VAULT_CERT_URI=$(terraform output -raw key_vault_certificate_uri)
ARGOCD_HOST=$(terraform output -raw argocd_hostname)

popd >/dev/null

# 1. Get kubeconfig for the AKS cluster.
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --overwrite-existing

# 2. Wait for the Argo CD extension to finish installing.
az k8s-extension show \
  --cluster-type managedClusters \
  --cluster-name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name argocd \
  --query "provisioningState" -o tsv

kubectl -n argocd rollout status deploy/argocd-server --timeout=10m

# 3. Patch the Argo CD ingress with the actual Key Vault certificate URI and
#    hostname, then apply.
sed \
  -e "s#https://<key-vault-name>.vault.azure.net/certificates/argocd-ingress-tls#${KEY_VAULT_CERT_URI}#g" \
  -e "s#argocd.example.com#${ARGOCD_HOST}#g" \
  k8s/argocd-ingress.yaml | kubectl apply -f -

# 4. Create a DNS A record for ${ARGOCD_HOST} that points at the App Routing
#    NGINX load balancer. The IP is published on the nginx service in the
#    `app-routing-system` namespace.
NGINX_IP=$(kubectl -n app-routing-system get svc nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "App Routing NGINX public IP: ${NGINX_IP}"
echo "Create an A record '${ARGOCD_HOST%%.*}' -> ${NGINX_IP} in your DNS zone."

# 5. Apply the sample Argo CD Application.
kubectl apply -f k8s/sample-application.yaml

# 6. Print the bootstrap admin password (use SSO once it's verified working).
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
