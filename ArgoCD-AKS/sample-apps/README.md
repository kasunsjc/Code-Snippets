# Sample Applications for ArgoCD

This directory contains sample Kubernetes applications and ArgoCD Application manifests to help you get started with GitOps.

## 📋 Contents

1. **Simple Application** - Basic nginx deployment
2. **ArgoCD Application** - ArgoCD Application CRD example
3. **Helm Application** - Deploy applications using Helm charts
4. **Kustomize Application** - Deploy applications using Kustomize
5. **Multi-Environment** - Example of deploying to multiple environments

## 🚀 Quick Start

### Deploy Sample Application

```bash
# Apply the sample deployment
kubectl apply -f 01-simple-app.yaml

# Verify deployment
kubectl get pods -n demo-app

# Access the application
kubectl port-forward -n demo-app svc/nginx-app 8080:80
```

### Create ArgoCD Application

```bash
# Apply ArgoCD Application manifest
kubectl apply -f 02-argocd-application.yaml

# Check application status
kubectl get application -n argocd

# View in ArgoCD UI or use CLI
argocd app get demo-app
argocd app sync demo-app
```

## 📦 Sample Manifests

### 01-simple-app.yaml
Basic nginx deployment with service and configmap.

### 02-argocd-application.yaml
ArgoCD Application CRD that deploys from a Git repository.

### 03-helm-application.yaml
Example of deploying a Helm chart through ArgoCD.

### 04-kustomize-application.yaml
Example of deploying with Kustomize overlays.

### 05-app-of-apps.yaml
App of Apps pattern for managing multiple applications.

## 🔄 GitOps Workflow

1. **Commit** changes to your Git repository
2. **ArgoCD detects** changes automatically (or manual sync)
3. **Sync** applies changes to the cluster
4. **Monitor** application health in ArgoCD UI

## 🛠️ Useful Commands

```bash
# List all applications
argocd app list

# Get application details
argocd app get <app-name>

# Sync application
argocd app sync <app-name>

# Delete application
argocd app delete <app-name>

# Set application to auto-sync
argocd app set <app-name> --sync-policy automated

# View application history
argocd app history <app-name>

# Rollback to previous version
argocd app rollback <app-name> <revision>
```

## 📚 Resources

- [ArgoCD Application Specification](https://argo-cd.readthedocs.io/en/stable/operator-manual/application.yaml)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/operator-manual/best_practices/)
- [GitOps Principles](https://www.gitops.tech/)
