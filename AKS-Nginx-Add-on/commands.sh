#!/bin/bash

export ResourceGroupName="aks-nginx-routing-rg"
export ClusterName="aks-nginx-routing"
export Location="northeurope"

# Login to Azure

az login

# Create a resource group

az group create --name $ResourceGroupName --location $Location

# Create an AKS cluster

az aks create --resource-group $ResourceGroupName --name $ClusterName --location $Location --enable-app-routing --generate-ssh-keys

# Get the credentials for the AKS cluster

az aks get-credentials --resource-group $ResourceGroupName --name $ClusterName --overwrite-existing

# Get the ingress class

kubectl get ingressclasses.networking.k8s.io

# Create an ingress IP address

kubectl get service -n app-routing-system

# Create a namespace for the application

kubectl create namespace hello-web-app-routing

# Deploy the application

kubectl apply  -n hello-web-app-routing -f ./sample-app.yaml

# Create an ingress resource

kubectl apply -n hello-web-app-routing -f ./ingress.yaml

