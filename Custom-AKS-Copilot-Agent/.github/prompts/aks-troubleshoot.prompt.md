# AKS Incident Troubleshooting Prompt

You are troubleshooting an AKS incident. Follow this checklist systematically.

## Pre-Flight Checks

Before diving into the specific issue, gather baseline cluster information:

```bash
# 1. Cluster info & connectivity
kubectl cluster-info
az aks show -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -o table

# 2. Node health
kubectl get nodes -o wide
kubectl top nodes

# 3. Cluster-wide events (last 30 min)
kubectl get events -A --sort-by='.lastTimestamp' | tail -50

# 4. System pods health
kubectl get pods -n kube-system -o wide

# 5. AKS provisioning state
az aks show -g <RESOURCE_GROUP> -n <CLUSTER_NAME> --query "provisioningState" -o tsv

# 6. Kubernetes version
kubectl version --short
```

## Node Troubleshooting

```bash
# Check node conditions
kubectl describe node <NODE_NAME> | grep -A 20 "Conditions:"

# Check node resource allocation
kubectl describe node <NODE_NAME> | grep -A 10 "Allocated resources:"

# Check node taints
kubectl describe node <NODE_NAME> | grep -A 5 "Taints:"

# AKS node pool details
az aks nodepool list -g <RESOURCE_GROUP> --cluster-name <CLUSTER_NAME> -o table

# VMSS instance status
az vmss list-instances -g MC_<RESOURCE_GROUP>_<CLUSTER_NAME>_<REGION> --name <VMSS_NAME> -o table
```

## Workload Troubleshooting

```bash
# Pod status across all namespaces
kubectl get pods -A -o wide | grep -v Running | grep -v Completed

# Describe the problematic pod
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Current logs
kubectl logs <POD_NAME> -n <NAMESPACE> --tail=100

# Previous container logs (for CrashLoopBackOff)
kubectl logs <POD_NAME> -n <NAMESPACE> --previous

# Multi-container pod logs
kubectl logs <POD_NAME> -n <NAMESPACE> -c <CONTAINER_NAME>

# Pod resource usage
kubectl top pod <POD_NAME> -n <NAMESPACE>

# Events for specific pod
kubectl get events -n <NAMESPACE> --field-selector involvedObject.name=<POD_NAME> --sort-by='.lastTimestamp'

# ReplicaSet / Deployment status
kubectl get deploy,rs -n <NAMESPACE> -o wide
kubectl describe deploy <DEPLOYMENT_NAME> -n <NAMESPACE>
```

## Networking Troubleshooting

```bash
# Service and endpoints
kubectl get svc -n <NAMESPACE>
kubectl get endpoints -n <NAMESPACE>
kubectl describe svc <SERVICE_NAME> -n <NAMESPACE>

# Ingress
kubectl get ingress -A
kubectl describe ingress <INGRESS_NAME> -n <NAMESPACE>

# Network policies
kubectl get networkpolicy -A
kubectl describe networkpolicy <POLICY_NAME> -n <NAMESPACE>

# DNS test
kubectl run dnstest --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default
kubectl run dnstest --image=busybox:1.36 --rm -it --restart=Never -- nslookup <SERVICE>.<NAMESPACE>.svc.cluster.local

# CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl logs -n kube-system -l k8s-app=coredns --tail=50

# Connectivity test from within cluster
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- curl -v http://<SERVICE>.<NAMESPACE>.svc.cluster.local

# AKS networking details
az aks show -g <RESOURCE_GROUP> -n <CLUSTER_NAME> --query "networkProfile" -o json

# Check NSG rules (for Azure CNI)
az network nsg list -g MC_<RESOURCE_GROUP>_<CLUSTER_NAME>_<REGION> -o table
```

## Storage Troubleshooting

```bash
# PV and PVC status
kubectl get pv
kubectl get pvc -n <NAMESPACE>
kubectl describe pvc <PVC_NAME> -n <NAMESPACE>

# Storage classes
kubectl get storageclass

# CSI driver pods
kubectl get pods -n kube-system | grep csi

# Check disk attachments on nodes
kubectl describe node <NODE_NAME> | grep -A 5 "Attachable"
```

## RBAC & Auth Troubleshooting

```bash
# Check permissions
kubectl auth can-i <VERB> <RESOURCE> -n <NAMESPACE> --as=<USER_OR_SA>
kubectl auth can-i list pods -n default --as=system:serviceaccount:default:my-sa

# List role bindings
kubectl get clusterrolebinding,rolebinding -A -o wide

# AKS AAD profile
az aks show -g <RESOURCE_GROUP> -n <CLUSTER_NAME> --query "aadProfile" -o json

# Service account details
kubectl get sa -n <NAMESPACE>
kubectl describe sa <SA_NAME> -n <NAMESPACE>
```

## AKS Upgrade Troubleshooting

```bash
# Current version and available upgrades
az aks show -g <RESOURCE_GROUP> -n <CLUSTER_NAME> --query "kubernetesVersion" -o tsv
az aks get-upgrades -g <RESOURCE_GROUP> -n <CLUSTER_NAME> -o table

# Check for deprecated APIs
kubectl get apiservice -o wide | grep -v Available

# PDBs that may block node drain
kubectl get pdb -A
kubectl describe pdb <PDB_NAME> -n <NAMESPACE>

# Node pool provisioning state
az aks nodepool list -g <RESOURCE_GROUP> --cluster-name <CLUSTER_NAME> -o table
```

## ACR Integration Troubleshooting

```bash
# Check ACR attachment
az aks check-acr -g <RESOURCE_GROUP> -n <CLUSTER_NAME> --acr <ACR_NAME>.azurecr.io

# Attach ACR to AKS
# ⚠️ This modifies cluster configuration
az aks update -g <RESOURCE_GROUP> -n <CLUSTER_NAME> --attach-acr <ACR_NAME>

# Verify image pull secrets
kubectl get secrets -n <NAMESPACE> | grep docker
kubectl describe secret <SECRET_NAME> -n <NAMESPACE>
```

## Performance & Scaling Troubleshooting

```bash
# HPA status
kubectl get hpa -A
kubectl describe hpa <HPA_NAME> -n <NAMESPACE>

# Metrics server
kubectl get apiservice v1beta1.metrics.k8s.io -o yaml
kubectl get pods -n kube-system | grep metrics-server

# Resource usage
kubectl top nodes
kubectl top pods -n <NAMESPACE> --sort-by=cpu
kubectl top pods -n <NAMESPACE> --sort-by=memory

# Cluster autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100

# AKS auto-scaler profile
az aks show -g <RESOURCE_GROUP> -n <CLUSTER_NAME> --query "autoScalerProfile" -o json
```
