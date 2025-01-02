#!/bin/bash

# Variables

export RESOURCE_GROUP_NAME="aks-nrg-lockdown"
export LOCATION="northeurope"
export CLUSTER_NAME="aks-nrg"
export NODE_RESOURCE_GROUP_NAME="aks-nrg-lockdown-nodes"

# Login to Azure

az login

# Enable preview extension

az extension add --name aks-preview

# Update to the latest version of the aks-preview extension
az extension update --name aks-preview

# Register the AKS preview feature for Node Resource Group Lockdown
FEATURE_STATUS=$(az feature show --namespace "Microsoft.ContainerService" --name "NRGLockdownPreview" --query properties.state -o tsv)

if [ "$FEATURE_STATUS" != "Registered" ]; then
  echo "Registering the NRGLockdownPreview feature..."
  az feature register --namespace "Microsoft.ContainerService" --name "NRGLockdownPreview"
  echo "Waiting for the feature to be registered..."
  while [ "$FEATURE_STATUS" != "Registered" ]; do
    sleep 10
    FEATURE_STATUS=$(az feature show --namespace "Microsoft.ContainerService" --name "NRGLockdownPreview" --query properties.state -o tsv)
  done
  echo "Feature NRGLockdownPreview is now registered."
else
  echo "Feature NRGLockdownPreview is already registered."
fi

# Register the provider 

az provider register --namespace Microsoft.ContainerService

# Create a Resource Group

echo "Creating Resource Group $RESOURCE_GROUP_NAME in $LOCATION"

az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

# Create a AKS Cluster without Node Resource Group lockdown

echo "Creating AKS Cluster with default Node Resource Group"
az aks create --name "$CLUSTER_NAME" --location $LOCATION --resource-group $RESOURCE_GROUP_NAME --generate-ssh-keys

echo "Sleeping for 60 seconds to allow the cluster to be created"
sleep 60

# Create a AKS cluster with Node Resource Group Lockdown

echo "Creating AKS Cluster with Node Resource Group Lockdown"
az aks create --name "$CLUSTER_NAME-lockdown" --location $LOCATION --resource-group $RESOURCE_GROUP_NAME --nrg-lockdown-restriction-level ReadOnly --generate-ssh-keys
