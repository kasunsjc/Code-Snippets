#!/bin/bash

cat <<EOF> .envrc
# Environment variables
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

# AKS
export AKS_CLUSTER_NAME="aks-labs"
export RESOURCE_GROUP="rg-aks-labs"
export LOCATION="westus3"
export MANAGED_IDENTITY_NAME="akspe"
EOF


# Create resource group
az group create --name ${RESOURCE_GROUP} --location ${LOCATION}

az aks create \
  --name ${AKS_CLUSTER_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --enable-managed-identity \
  --node-count 3 \
  --generate-ssh-keys \
  --enable-oidc-issuer \
  --enable-workload-identity


az aks get-credentials \
  --name ${AKS_CLUSTER_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --file aks-labs.config

export KUBECONFIG=$PWD/aks-labs.config


export AKS_OIDC_ISSUER_URL=$(az aks show \
  --resource-group ${RESOURCE_GROUP} \
  --name ${AKS_CLUSTER_NAME} \
  --query "oidcIssuerProfile.issuerUrl" \
  -o tsv)

az identity create \
  --name "${MANAGED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}"


export AZURE_CLIENT_ID=$(az identity show \
  --name "${MANAGED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "clientId" -o tsv)

export PRINCIPAL_ID=$(az identity show \
  --name "${MANAGED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "principalId" -o tsv)


# Print the environment variables (for verification)
echo "AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
echo "AZURE_TENANT_ID: $AZURE_TENANT_ID"
echo "AZURE_CLIENT_ID: $AZURE_CLIENT_ID"
echo "PRINCIPAL_ID: $PRINCIPAL_ID"  

# Append the variables to .envrc
echo export AKS_OIDC_ISSUER_URL=${AKS_OIDC_ISSUER_URL} >> .envrc
echo export AZURE_CLIENT_ID=${AZURE_CLIENT_ID} >> .envrc
echo export PRINCIPAL_ID=${PRINCIPAL_ID} >>  .envrc

az role assignment create \
  --assignee "${PRINCIPAL_ID}" \
  --role "Contributor" \
  --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}"

az role assignment create \
  --assignee "${PRINCIPAL_ID}" \
  --role "Managed Identity Operator" \
  --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${MANAGED_IDENTITY_NAME}"

az identity federated-credential create \
  --name "aks-labs-capz-manager-credential" \
  --identity-name "${MANAGED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --issuer "${AKS_OIDC_ISSUER_URL}" \
  --subject "system:serviceaccount:azure-infrastructure-system:capz-manager" \
  --audiences "api://AzureADTokenExchange"

az identity federated-credential create \
  --name "serviceoperator" \
  --identity-name "${MANAGED_IDENTITY_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --issuer "${AKS_OIDC_ISSUER_URL}" \
  --subject "system:serviceaccount:azure-infrastructure-system:azureserviceoperator-default" \
  --audiences "api://AzureADTokenExchange"

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait for ArgoCD to be ready
kubectl get pods -n argocd -w

# Get argocd admin password
kubectl get secrets argocd-initial-admin-secret -n argocd --template="{{index .data.password | base64decode}}" ; echo


# Install Cert Manager
# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager with CRDs (adjust the namespace if needed)
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --version v1.15.3  # Use the latest stable version

# Wait for cert-manager to be ready
kubectl get pods -n cert-manager

# Install CAPI Operators
cat <<EOF> capi-operator-values.yaml
core:
  cluster-api:
    version: v1.9.6
infrastructure:
  azure:
    version: v1.19.2
addon:
  helm:
    version: v0.3.1
manager:
  featureGates:
    core:
      ClusterTopology: true
      MachinePool: true
additionalDeployments:
  azureserviceoperator-controller-manager:
    deployment:
      containers:
        - name: manager
          args:
            --crd-pattern: "resources.azure.com/*;containerservice.azure.com/*;keyvault.azure.com/*;managedidentity.azure.com/*;eventhub.azure.com/*;storage.azure.com/*"
EOF

# Install Cluster API Azure Provider
helm repo add capi-operator https://kubernetes-sigs.github.io/cluster-api-operator
helm repo update
helm install capi-operator capi-operator/cluster-api-operator \
  --create-namespace -n capi-operator-system \
  --wait \
  --timeout=300s \
  -f capi-operator-values.yaml

# For Upgrades use the following command

  helm upgrade --install install capi-operator capi-operator/cluster-api-operator \
  --create-namespace -n capi-operator-system \
  --wait \
  --timeout=300s \
  -f capi-operator-values.yaml

# Wait for CAPI to be ready
kubectl get pods -n azure-infrastructure-system


# Generate CAPZ AzureClusterIdentiry
cat <<EOF> identity.yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AzureClusterIdentity
metadata:
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/sync-wave: "5"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
  labels:
    clusterctl.cluster.x-k8s.io/move-hierarchy: "true"
  name: cluster-identity
  namespace: azure-infrastructure-system
spec:
  allowedNamespaces: {}
  clientID: ${AZURE_CLIENT_ID}
  tenantID: ${AZURE_TENANT_ID}
  type: WorkloadIdentity
EOF

# Apply the AzureClusterIdentity
kubectl apply -f identity.yaml