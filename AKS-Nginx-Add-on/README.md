# AKS NGINX Application Routing Add-on

Deploy the NGINX Ingress Controller as a native AKS add-on with SSL/TLS termination support.

## 📋 Overview

The Application Routing add-on for AKS provides an easy-to-configure ingress controller backed by NGINX. This demo covers basic setup and advanced SSL termination with Azure Key Vault and DNS integration.

## 📁 Contents

```
AKS-Nginx-Add-on/
├── README.md                    # This documentation
├── script.js                    # Utility scripts
├── Create-AKS-Nginx-Add-On/     # Basic NGINX add-on setup
│   ├── commands.sh              # Deployment commands
│   ├── sample-app.yaml          # Sample application
│   └── ingress.yaml             # Ingress configuration
└── SSL-With-KeyVault-AzureDNS/  # Advanced SSL/TLS setup
    ├── commands.sh              # SSL configuration commands
    ├── sample-app.yaml          # Sample application
    └── ingress.yaml             # SSL-enabled ingress
```

## 🚀 Quick Start

### Basic NGINX Add-on

```bash
cd Create-AKS-Nginx-Add-On
./commands.sh
```

This will:
1. Create a resource group and AKS cluster with app routing enabled
2. Deploy a sample application
3. Configure ingress routing

### SSL/TLS with Key Vault

```bash
cd SSL-With-KeyVault-AzureDNS
./commands.sh
```

This will:
1. Create Azure Key Vault with RBAC
2. Import SSL certificate
3. Configure AKS to use Key Vault
4. Set up DNS zone integration
5. Deploy application with SSL termination

## 🔧 Key Features

### Basic Setup
- Native AKS integration (no Helm required)
- Automatic ingress class configuration
- Simple deployment with `--enable-app-routing` flag

### SSL/TLS Features
- Azure Key Vault certificate integration
- Automatic certificate rotation
- Azure DNS zone management
- RBAC-based access control

## 📋 Prerequisites

- Azure CLI with latest version
- kubectl configured
- Azure subscription with permissions for:
  - AKS cluster creation
  - Key Vault management
  - DNS zone management

## 💡 Configuration Examples

### Create AKS with App Routing

```bash
az aks create \
  --resource-group $ResourceGroupName \
  --name $ClusterName \
  --location $Location \
  --enable-app-routing \
  --generate-ssh-keys
```

### Enable Key Vault Integration

```bash
KEYVAULTID=$(az keyvault show --name $KeyVaultName --query "id" --output tsv)
az aks approuting update \
  --resource-group $ResourceGroupName \
  --name $ClusterName \
  --enable-kv \
  --attach-kv ${KEYVAULTID}
```

### Attach DNS Zone

```bash
ZONEID=$(az network dns zone show --resource-group $DNSZoneResourceGroup --name $ZoneName --query "id" --output tsv)
az aks approuting zone add \
  --resource-group $ResourceGroupName \
  --name $ClusterName \
  --ids=${ZONEID} \
  --attach-zones
```

## 📚 Learn More

- [Application Routing Add-on Overview](https://learn.microsoft.com/azure/aks/app-routing)
- [SSL/TLS with Key Vault](https://learn.microsoft.com/azure/aks/app-routing-dns-ssl)
- [External DNS Integration](https://learn.microsoft.com/azure/aks/app-routing-dns-ssl#configure-external-dns)

## 📄 License

This demo is provided for educational purposes.
