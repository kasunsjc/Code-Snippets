#!/bin/bash

###########################################
# Before we use the SSL teminations we should have a valid certificate. 
# If you have a valid certificate for the domain you can use it.
# If you don't have a valid certificate you can create a self-signed certificate.
# 
# To deploy the AKS cluster with App routing addon, you can use the follow the steps in the root of this folder.
###########################################

export ResourceGroupName="aks-nginx-routing-rg"
export ClusterName="aks-nginx-routing"
export Location="northeurope"
export KeyVaultName="aks-nginx-routing-kv"
export CertificateName="aks-ingress-tls"
export ZoneName="<DNSZoneName>"
export DNSZoneResourceGroup="aks-demo-cluster-sea-rg"
export SubscriptionId="<SubID>"

# Login to Azure

az login

# Create a Key Vault

az keyvault create --resource-group $ResourceGroupName --location $Location --name $KeyVaultName --enable-rbac-authorization true

# Assign the Key Vault RBAC role to user

az role assignment create --role "Key Vault Certificates Officer" --assignee kasunr@infrakloud.com --scope "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName"

# Import the certificate to the Key Vault
# certificate file should be in .pfx format
az keyvault certificate import --vault-name $KeyVaultName --name $CertificateName --file star_kasunrajapakse_xyz.pfx 

# Enable the Key Vault for the AKS cluster

KEYVAULTID=$(az keyvault show --name $KeyVaultName --query "id" --output tsv) # Get the Key Vault ID

az aks approuting update --resource-group $ResourceGroupName --name $ClusterName --enable-kv --attach-kv ${KEYVAULTID}

# Create a public DNS zone (if you don't have one)

#az network dns zone create --resource-group $ResourceGroupName --name <ZoneName>

# if you have a public DNS zone, you can use it

ZONEID=$(az network dns zone show --resource-group $DNSZoneResourceGroup --name $ZoneName --query "id" --output tsv)

# Update the DNS zone to use the App routing addon

az aks approuting zone add --resource-group $ResourceGroupName --name $ClusterName --ids=${ZONEID} --attach-zones

# Get the Certificate URI from the Key Vault. This URI will be used in the Ingress resource

az keyvault certificate show --vault-name $KeyVaultName --name $CertificateName --query "id" --output tsv

# Get AKS cluster credentials

az aks get-credentials --resource-group $ResourceGroupName --name $ClusterName --overwrite-existing

# Create namespace for the sample application

kubectl create namespace app-routing-ssl-demo

# Deploy Sample Application

kubectl apply -n app-routing-ssl-demo -f ./sample-app.yaml

# Create Ingress with SSL termination

kubectl apply -n app-routing-ssl-demo -f ./ingress.yaml