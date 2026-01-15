# ArgoCD on Azure Kubernetes Service (AKS)

This demo provides a complete Infrastructure as Code (IaC) solution for deploying ArgoCD on Azure Kubernetes Service using Bicep templates and Helm.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Accessing ArgoCD](#accessing-argocd)
- [Sample Applications](#sample-applications)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

## 🎯 Overview

This demo showcases:
- **Infrastructure as Code**: Complete Bicep templates for AKS deployment
- **ArgoCD Installation**: Production-ready ArgoCD setup with HA configuration
- **Traefik Ingress**: Automatic TLS with Let's Encrypt certificates
- **Cert-Manager**: Automated certificate management
- **GitOps Ready**: Sample applications and ArgoCD configurations
- **Azure Integration**: Monitoring, networking, and security best practices
- **Custom Domain**: Access ArgoCD via `argo-demo.kasunrajapakse.xyz`

## 🏗️ Architecture

The deployment creates the following Azure and Kubernetes resources:

```
├── Resource Group
│   ├── Virtual Network (10.0.0.0/16)
│   │   └── AKS Subnet (10.0.0.0/22)
│   ├── AKS Cluster
│   │   ├── System Node Pool (3-5 nodes with autoscaling)
│   │   ├── Azure CNI Networking
│   │   ├── Workload Identity (enabled)
│   │   └── Key Vault Secrets Provider
│   └── Log Analytics Workspace
```

Kubernetes components deployed:
- **Traefik Ingress Controller**: 2+ replicas with autoscaling, LoadBalancer service
- **Cert-Manager**: Automatic TLS certificate management with Let's Encrypt
- **ArgoCD Server**: 2+ replicas with autoscaling (ClusterIP + Ingress)
- **ArgoCD Repo Server**: 2+ replicas with autoscaling
- **ArgoCD Application Controller**: 1 replica
- **Redis HA**: 3 replicas with HAProxy
- **ApplicationSet Controller**: 2 replicas
- **Notifications Controller**: For Slack/Teams/Email notifications

## ✅ Prerequisites

Before you begin, ensure you have the following tools installed:

1. **Azure CLI** (v2.50.0 or later)
   ```bash
   # macOS
   brew install azure-cli
   
   # Linux
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   
   # Windows
   winget install Microsoft.AzureCLI
   ```

2. **kubectl** (v1.28.0 or later)
   ```bash
   # macOS
   brew install kubectl
   
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   
   # Windows
   winget install Kubernetes.kubectl
   ```

3. **Helm** (v3.12.0 or later)
   ```bash
   # macOS
   brew install helm
   
   # Linux
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   
   # Windows
   winget install Helm.Helm
   ```

4. **ArgoCD CLI** (optional, for CLI operations)
   ```bash
   # macOS
   brew install argocd
   
   # Linux
   curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
   sudo install -m 555 argocd /usr/local/bin/argocd
   
   # Windows
   winget install ArgoProj.ArgoCD
   ```

5. **Azure Subscription**: You need an active Azure subscription with permissions to create resources.

## 🚀 Quick Start

### 1. Clone or Navigate to the Repository

```bash
cd ArgoCD-AKS
```

### 2. Review and Update Configuration

Edit [main.bicepparam](main.bicepparam) to customize your deployment:

```bicep
param location = 'eastus'              # Change to your preferred region
param environmentName = 'dev'          # dev, staging, prod, etc.
param baseName = 'argocd'              # Base name for resources

param aksConfig = {
  kubernetesVersion: '1.30.0'          # Update to desired K8s version
  nodeCount: 3                         # Initial node count
  nodeVmSize: 'Standard_D4s_v3'        # VM size for nodes
  # ... other settings
}
```

### 3. Login to Azure

```bash
az login
az account set --subscription "your-subscription-name"
```

### 4. Deploy Everything

Make the deployment script executable and run it:

```bash
chmod +x deploy.sh
./deploy.sh
```

The script will:
1. ✅ Deploy Azure infrastructure (VNet, AKS, Log Analytics)
2. ✅ Configure kubectl with AKS credentials
3. ✅ Install cert-manager for TLS certificate management
4. ✅ Install Traefik ingress controller
5. ✅ Install ArgoCD with HA configuration
6. ✅ Create IngressRoute for HTTPS access
7. ✅ Display access credentials and configuration instructions

### 5. Configure DNS

After deployment, configure your DNS:

1. Get the Traefik LoadBalancer IP from the deployment output
2. Create an A record: `argo-demo.kasunrajapakse.xyz` → `<TRAEFIK-IP>`
3. Wait for DNS propagation (usually 1-5 minutes)

See [DNS-SETUP.md](DNS-SETUP.md) for detailed DNS configuration instructions.

### 6. Access ArgoCD

After DNS is configured and the certificate is issued (2-5 minutes):
Infrastructure Configuration

Modify [main.bicepparam](main.bicepparam) for infrastructure changes:

- **Node Pool**: Change `nodeVmSize`, `nodeCount`, or add additional node pools
- **Networking**: Adjust CIDR ranges in `networkConfig` (default: /22 subnet for Azure CNI)
- **Monitoring**: Configure Log Analytics retention

### Traefik Configuration

The [traefik-values.yaml](traefik-values.yaml) configures:
- LoadBalancer service with 2+ replicas
- Automatic HTTPS with Let's Encrypt
- Metrics and dashboard
- Autoscaling based on CPU/memory

### Cert-Manager Configuration

The [cert-manager-values.yaml](cert-manager-values.yaml) and [manifests/cluster-issuer.yaml](manifests/cluster-issuer.yaml) configure:
- Let's Encrypt staging and production issuers
- HTTP-01 challenge solver
- Automatic certificate renewal

### 
```
URL: https://argo-demo.kasunrajapakse.xyz
Username: admin
Password: <shown in deployment output>
```

**Alternative (Port Forward):**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Access at: http://localhost:8080
```

## ⚙️ Configuration

### ArgoCD Values Configuration
Ingress Configuration

ArgoCD is exposed via Traefik IngressRoute (see [manifests/argocd-ingress.yaml](manifests/argocd-ingress.yaml)):

```yaml
# IngressRoute handles HTTPS traffic with automatic TLS
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`argo-demo.kasunrajapakse.xyz`)
      services:
        - name: argocd-server
          port: 80
  tls:
    certResolver: letsencrypt  # Automatic TLS from Let's Encrypt
```

The deployment uses ClusterIP service with Traefik ingress instead of LoadBalancer.
#### High Availability

```yaml
redis-ha:
  enabled: true
  replicas: 3

server:
  replicas: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5

repoServer:
  replicas: 2
  autoscaling:
    enabled: true
```

#### Service Type

By default, ArgoCD is exposed via LoadBalancer:

```yaml
server:
  service:
    type: LoadBalancer
```

For Ingress-based access (after installing an ingress controller):

```yaml
server:
  service:
    type: ClusterIP
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - argocd.example.com
```

#### SSO Configuration (Optional)

Configure Azure AD authentication:

```yaml
server:
  config:
    oidc.config: |
      name: Azure AD
      issuer: https://login.microsoftonline.com/<tenant-id>/v2.0
      clientID: <client-id>
      clientSecret: $oidc.azure.clientSecret
```

#### Notifications

Configure Slack, Teams, or email notifications:

```yaml
notifications:
  enabled: true
  notifiers:
    service.slack: |
      token: $slack-token
```

## 🌐 Accessing ArgoCD

### Method 1: HTTPS via Custom Domain (Recommended)

Access ArgoCD via your custom domain with automatic HTTPS:

```bash
# After DNS is configured
https://argo-demo.kasunrajapakse.xyz
```

Benefits:
- ✅ Automatic TLS certificate from Let's Encrypt
- ✅ Secure HTTPS connection
- ✅ Easy to remember URL
- ✅ Works with ArgoCD CLI

See [DNS-SETUP.md](DNS-SETUP.md) for detailed configuration instructions.

### Method 2: Port Forward (Development/Testing)

For quick access without DNS configuration:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Access at http://localhost:8080
```

### Method 3: ArgoCD CLI

```bash
# Login to ArgoCD
argocd login argo-demo.kasunrajapakse.xyz --username admin --password <password>

# Or with port-forward
argocd login localhost:8080 --username admin --password <password> --insecure

# List applications
argocd app list

# Get application details
argocd app get <app-name>
```

## 📦 Sample Applications

### Deploy Sample Application

The `sample-apps/` directory contains example applications and ArgoCD configurations:

```bash
cd sample-apps

# Deploy the sample application
kubectl apply -f 01-simple-app.yaml
```

### Create ArgoCD Application

```bash
# Apply ArgoCD Application manifest
kubectl apply -f 02-argocd-application.yaml
```

See the [sample-apps/README.md](sample-apps/README.md) for more examples.

## 🧹 Cleanup

To remove all resources:

```bash
chmod +x cleanup.sh
./cleanup.sh
```

This will:
1. Delete all ArgoCD applications
2. Uninstall ArgoCD Helm release
3. Delete the ArgoCD namespace
4. Delete the Azure resource group and all resources

## 🔧 Troubleshooting

### Common Issues

#### 1. Cannot Access ArgoCD via HTTPS

Check DNS and certificate:

```bash
# Verify DNS resolves correctly
dig argo-demo.kasunrajapakse.xyz +short
nslookup argo-demo.kasunrajapakse.xyz

# Check certificate status
kubectl get certificate -n argocd
kubectl describe certificate -n argocd

# Check IngressRoute
kubectl get ingressroute -n argocd
kubectl describe ingressroute argocd-server -n argocd
```

#### 2. Certificate Not Issued

```bash
# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Check challenges
kubectl get challenges -A
kubectl describe challenge <challenge-name> -n argocd

# Check ClusterIssuer
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

See [DNS-SETUP.md](DNS-SETUP.md) for detailed troubleshooting.

#### 3. Traefik Issues

```bash
# Check Traefik pods
kubectl get pods -n traefik

# Check Traefik service (LoadBalancer)
kubectl get svc traefik -n traefik

# View Traefik logs
kubectl logs -n traefik deployment/traefik -f

# Access Traefik dashboard
kubectl port-forward -n traefik svc/traefik 9000:9000
# Then open: http://localhost:9000/dashboard/
```

#### 4. ArgoCD Server Not Accessible

```bash
# Check if pods are running
kubectl get pods -n argocd

# Check service status
kubectl get svc argocd-server -n argocd

# View logs
kubectl logs -n argocd deployment/argocd-server -f
```

#### 5. Authentication Issues

Reset the admin password:

```bash
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Or change password via CLI
argocd account update-password
```

#### 6. AKS Cluster Issues

```bash
# Check cluster status
az aks show --resource-group <rg-name> --name <aks-name> --query provisioningState

# Get cluster credentials
az aks get-credentials --resource-group <rg-name> --name <aks-name> --overwrite-existing

# Check node status
kubectl get nodes
```

### Logs and Diagnostics

```bash
# View ArgoCD application controller logs
kubectl logs -n argocd deployment/argocd-application-controller -f

# View repo server logs
kubectl logs -n argocd deployment/argocd-repo-server -f

# View server logs
kubectl logs -n argocd deployment/argocd-server -f

# View Traefik logs
kubectl logs -n traefik deployment/traefik -f

# View cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Check all ArgoCD events
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

## 📚 Additional Resources

### Documentation
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/operator-manual/best_practices/)
- [AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Helm Chart Values](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)

### Related Files
- [DNS-SETUP.md](DNS-SETUP.md) - Detailed DNS and TLS certificate setup
- [argocd-values.yaml](argocd-values.yaml) - ArgoCD Helm configuration
- [traefik-values.yaml](traefik-values.yaml) - Traefik Helm configuration
- [cert-manager-values.yaml](cert-manager-values.yaml) - Cert-Manager configuration
- [manifests/cluster-issuer.yaml](manifests/cluster-issuer.yaml) - Let's Encrypt issuers
- [manifests/argocd-ingress.yaml](manifests/argocd-ingress.yaml) - ArgoCD IngressRoute

## 🤝 Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## 📝 License

This project is provided as-is for demonstration purposes.

---

**Happy GitOps with ArgoCD! 🚀**
