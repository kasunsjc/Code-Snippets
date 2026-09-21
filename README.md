# Code Snippets Repository 🚀

Welcome to the **Code Snippets Repository**! This repository contains sample code, demos, and tutorials for Azure Kubernetes Service (AKS), Docker, and container technologies. Perfect for learning, blog posts, and YouTube tutorials.

<!-- AUTO-GENERATED CONTENT BELOW - DO NOT EDIT MANUALLY -->
<!-- Last updated by GitHub Actions -->

> **33 examples** | Kubernetes: 21 | Docker: 4 | Azure: 1 | *Last Updated: September 2026*

## 📝 Related Blog Posts

Looking for the full walkthroughs behind some of these samples? Visit the
[Kasun Rajapakse blog](https://kasunrajapakse.me/blog/) for the companion
articles linked below.

| Blog Post | Code Sample |
|---|---|
| [Advanced Container Networking Services on AKS: X-Ray Vision and Kernel-Level Guardrails for Your Cluster Network](https://kasunrajapakse.me/blog/aks-advanced-container-networking-services/) | [AKS Advanced Container Networking Services (ACNS) with Cilium — Terraform](./AKS-ACNS-Cilium-Terraform/) |
| [Deploying the AKS Argo CD Extension with App Routing Ingress and Entra ID SSO](https://kasunrajapakse.me/blog/aks-argo-cd-extension-app-routing-entra-id-sso/) | [AKS Argo CD Extension with Microsoft Entra SSO](./AKS-ArgoCD-Extension/) |
| [Harbor Audit Logs in Azure Log Analytics: A Fluent Bit Bridge](https://kasunrajapakse.me/blog/harbor-audit-logs-azure-log-analytics/) | [Harbor on AKS — Terraform + Traefik + cert-manager + Azure DNS](./AKS-Harbor-Registry-Demo/) |
| [Monitoring Harbor with Azure Monitor and Azure Managed Grafana](https://kasunrajapakse.me/blog/monitor-harbor-azure-monitor-managed-grafana/) | [Harbor on AKS — Terraform + Traefik + cert-manager + Azure DNS](./AKS-Harbor-Registry-Demo/) |
| [Migrating AKS Ingress to Istio-Based Gateway API: Moving Beyond NGINX](https://kasunrajapakse.me/blog/aks-istio-gateway-api/) | [AKS Istio Gateway API Demo](./AKS-Istio-Gateway-API/) |
| [Scaling AKS Workloads on Custom Metrics with KEDA and Azure Managed Prometheus](https://kasunrajapakse.me/blog/aks-keda-managed-prometheus-scaler/) | [AKS KEDA Demo](./AKS-KEDA-Demo/) |
| [Why You Should Never Lock AKS-Managed Resources: A Volume Outage Story](https://kasunrajapakse.me/blog/aks-resource-locks-managed-disks-incident/) | [AKS Node Resource Group Lockdown](./AKS-NodeRG-Lockdown/) |
| [Advanced Container Networking Services on AKS: X-Ray Vision and Kernel-Level Guardrails for Your Cluster Network](https://kasunrajapakse.me/blog/aks-advanced-container-networking-services/) | [BYO CNI on AKS with Cilium](./BYO-CNI-AKS/) |
| [Runtime Threat Detection on AKS with Falco and Microsoft Sentinel](https://kasunrajapakse.me/blog/falco-aks-sentinel-runtime-security/) | [Falco on AKS with Azure Sentinel Integration Demo](./Falco-AKS-Sentinel/) |

## 📋 Table of Contents

| # | Demo | Description | Category |
|---|------|-------------|----------|
| 1 | [ACR-Task](./ACR-Task/) | Build container images directly in Azure without needing Docker installed locally. | Azure |
| 2 | [AKS-ACNS-Cilium-Terraform](./AKS-ACNS-Cilium-Terraform/) | Deep network traffic visibility and security on Azure Kubernetes Service using **Advanced Contain... | Kubernetes |
| 3 | [AKS-AppGW-Containers](./AKS-AppGW-Containers/) | Deploy an AKS cluster using **Application Gateway for Containers** — the next generation of Azure... | Kubernetes |
| 4 | [AKS-Application-Network](./AKS-Application-Network/) | No description available | Kubernetes |
| 5 | [AKS-ArgoCD-Extension](./AKS-ArgoCD-Extension/) | End-to-end Terraform automation that deploys [Argo CD](https://argo-cd.readthedocs.io/) on Azure ... | Kubernetes |
| 6 | [AKS-Blue-Green-NodePool](./AKS-Blue-Green-NodePool/) | No description available | Kubernetes |
| 7 | [AKS-Desktop](./AKS-Desktop/) | This demo shows how **AKS Desktop** works and how to use **Azure Managed Projects** to deploy and... | Kubernetes |
| 8 | [AKS-Fleet-Manager-Demo](./AKS-Fleet-Manager-Demo/) | A comprehensive demonstration of Azure Kubernetes Service (AKS) Fleet Manager capabilities, showc... | Kubernetes |
| 9 | [AKS-Harbor-Production-Demo](./AKS-Harbor-Production-Demo/) | No description available | Kubernetes |
| 10 | [AKS-Harbor-Registry-Demo](./AKS-Harbor-Registry-Demo/) | A basic Harbor container registry install on AKS via Helm, with Terraform provisioning | Kubernetes |
| 11 | [AKS-Istio-Gateway-API](./AKS-Istio-Gateway-API/) | > **Blog Reference:** [Announcing Gateway API support for App Routing (preview) — AKS Blog, March... | Kubernetes |
| 12 | [AKS-Istio-Service-Mesh-Demo](./AKS-Istio-Service-Mesh-Demo/) | A hands-on deep dive into the **Istio-based service mesh add-on for Azure Kubernetes Service (AKS... | Kubernetes |
| 13 | [AKS-KEDA-Demo](./AKS-KEDA-Demo/) | A hands-on demo showing how **KEDA (Kubernetes Event-Driven Autoscaling)** works on | Kubernetes |
| 14 | [AKS-Monitoring](./AKS-Monitoring/) | This guide provides an overview of how to monitor Azure Kubernetes Service (AKS) using Azure Moni... | Kubernetes |
| 15 | [AKS-Nginx-Add-on](./AKS-Nginx-Add-on/) | Deploy the NGINX Ingress Controller as a native AKS add-on with SSL/TLS termination support. | Kubernetes |
| 16 | [AKS-Node-Autoprovision](./AKS-Node-Autoprovision/) | Automatically provision AKS nodes based on workload requirements without managing node pools manu... | Kubernetes |
| 17 | [AKS-NodeRG-Lockdown](./AKS-NodeRG-Lockdown/) | Enhance AKS security by restricting access to node resource group resources. | Kubernetes |
| 18 | [AKS-OPA-Policy-Demo](./AKS-OPA-Policy-Demo/) | This demo provisions an AKS cluster with the **Azure Policy Add-on** enabled and | Kubernetes |
| 19 | [Agentic-CLI-AKS](./Agentic-CLI-AKS/) | > ⚠️ **Preview Feature** - This is an experimental Azure CLI extension currently in preview. Not ... | Kubernetes |
| 20 | [Azure-Copilot-AKS-Troubleshooting](./Azure-Copilot-AKS-Troubleshooting/) | This demo shows how to use **Microsoft Copilot in Azure** (Azure Portal Copilot) to troubleshoot ... | Other |
| 21 | [Azure-Private-Link-Demo](./Azure-Private-Link-Demo/) | No description available | Other |
| 22 | [BYO-CNI-AKS](./BYO-CNI-AKS/) | Deploy an AKS cluster using **Bring Your Own CNI (BYO CNI)** and install **Cilium** as the Contai... | Kubernetes |
| 23 | [Custom-AKS-Copilot-Agent](./Custom-AKS-Copilot-Agent/) | A custom GitHub Copilot agent specialized in Azure Kubernetes Service (AKS) and Kubernetes troubl... | Kubernetes |
| 24 | [Docker-Hardened-Images](./Docker-Hardened-Images/) | Welcome to this comprehensive demo on **Docker Hardened Images**! This repository demonstrates Do... | Docker |
| 25 | [Docker-Offload](./Docker-Offload/) | > **Demonstrating Docker's new cloud execution feature for building and running containers** | Docker |
| 26 | [Docker-Sandboxes-Demo](./Docker-Sandboxes-Demo/) | > **Experimental Feature** - Requires Docker Desktop 4.50 or later | Docker |
| 27 | [Docker-Scout](./Docker-Scout/) | Detect and remediate vulnerabilities in your container images with Docker Scout. | Docker |
| 28 | [Falco-AKS-Sentinel](./Falco-AKS-Sentinel/) | This repository contains the complete Infrastructure as Code (IaC) and configuration for demonstr... | Other |
| 29 | [K6-Load-Testing-Demo](./K6-Load-Testing-Demo/) | No description available | Other |
| 30 | [Kyverno-Policy-Demo](./Kyverno-Policy-Demo/) | No description available | Other |
| 31 | [Platform-Enginering-AKS-ArgoCD-ASO](./Platform-Enginering-AKS-ArgoCD-ASO/) | No description available | Kubernetes |
| 32 | [VCluster-Demo](./VCluster-Demo/) | No description available | Other |
| 33 | [plan](./plan/) | No description available | Other |

---

## 📁 Examples by Category

### Kubernetes

- **[AKS-ACNS-Cilium-Terraform](./AKS-ACNS-Cilium-Terraform/)** — Deep network traffic visibility and security on Azure Kubernetes Service using **Advanced Container Networking Services** with **Azure CNI Powered by Cilium**, provisioned entirely with **Terraform**.
  - 📄 README: Yes | 📁 Files: 22
- **[AKS-AppGW-Containers](./AKS-AppGW-Containers/)** — Deploy an AKS cluster using **Application Gateway for Containers** — the next generation of Azure Application Gateway designed for Kubernetes workloads. This demo uses the **Gateway API** (the successor to Ingress) with the ALB Controller AKS add-on.
  - 📄 README: Yes | 📁 Files: 23
- **[AKS-Application-Network](./AKS-Application-Network/)** — No description available
  - 📄 README: No | 📁 Files: 0
- **[AKS-ArgoCD-Extension](./AKS-ArgoCD-Extension/)** — End-to-end Terraform automation that deploys [Argo CD](https://argo-cd.readthedocs.io/) on Azure Kubernetes Service (AKS) using the **`Microsoft.ArgoCD` cluster extension**, with Microsoft Entra ID single sign-on, group-based RBAC, TLS from Azure Key Vault, and automatic DNS via the App Routing add-on — all in a single `./deploy.sh` invocation.
  - 📄 README: Yes | 📁 Files: 26
- **[AKS-Blue-Green-NodePool](./AKS-Blue-Green-NodePool/)** — No description available
  - 📄 README: No | 📁 Files: 0
- **[AKS-Desktop](./AKS-Desktop/)** — This demo shows how **AKS Desktop** works and how to use **Azure Managed Projects** to deploy and manage applications. We use an **AKS Automatic** cluster because Managed Projects only work with AKS Automatic.
  - 📄 README: Yes | 📁 Files: 8
- **[AKS-Fleet-Manager-Demo](./AKS-Fleet-Manager-Demo/)** — A comprehensive demonstration of Azure Kubernetes Service (AKS) Fleet Manager capabilities, showcasing multi-cluster orchestration, resource propagation, and centralized management.
  - 📄 README: Yes | 📁 Files: 22
- **[AKS-Harbor-Production-Demo](./AKS-Harbor-Production-Demo/)** — No description available
  - 📄 README: No | 📁 Files: 13
- **[AKS-Harbor-Registry-Demo](./AKS-Harbor-Registry-Demo/)** — A basic Harbor container registry install on AKS via Helm, with Terraform provisioning
  - 📄 README: Yes | 📁 Files: 19
- **[AKS-Istio-Gateway-API](./AKS-Istio-Gateway-API/)** — > **Blog Reference:** [Announcing Gateway API support for App Routing (preview) — AKS Blog, March 2026](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api)
  - 📄 README: Yes | 📁 Files: 10
- **[AKS-Istio-Service-Mesh-Demo](./AKS-Istio-Service-Mesh-Demo/)** — A hands-on deep dive into the **Istio-based service mesh add-on for Azure Kubernetes Service (AKS)**: what it actually installs, mutual TLS, traffic management (canary/weighted routing, header-based routing, fault injection), zero-trust authorization policies, ingress, observability, and — critically — where the managed add-on's guardrails stop and when you should reach for a self-managed, open-source Istio install instead.
  - 📄 README: Yes | 📁 Files: 22
- **[AKS-KEDA-Demo](./AKS-KEDA-Demo/)** — A hands-on demo showing how **KEDA (Kubernetes Event-Driven Autoscaling)** works on
  - 📄 README: Yes | 📁 Files: 88
- **[AKS-Monitoring](./AKS-Monitoring/)** — This guide provides an overview of how to monitor Azure Kubernetes Service (AKS) using Azure Monitor, integrate with Azure Managed Grafana, and set up Azure Alerts with Azure Monitor recording and alert rules.
  - 📄 README: Yes | 📁 Files: 3
- **[AKS-Nginx-Add-on](./AKS-Nginx-Add-on/)** — Deploy the NGINX Ingress Controller as a native AKS add-on with SSL/TLS termination support.
  - 📄 README: Yes | 📁 Files: 10
- **[AKS-Node-Autoprovision](./AKS-Node-Autoprovision/)** — Automatically provision AKS nodes based on workload requirements without managing node pools manually.
  - 📄 README: Yes | 📁 Files: 4
- **[AKS-NodeRG-Lockdown](./AKS-NodeRG-Lockdown/)** — Enhance AKS security by restricting access to node resource group resources.
  - 📄 README: Yes | 📁 Files: 2
- **[AKS-OPA-Policy-Demo](./AKS-OPA-Policy-Demo/)** — This demo provisions an AKS cluster with the **Azure Policy Add-on** enabled and
  - 📄 README: Yes | 📁 Files: 73
- **[Agentic-CLI-AKS](./Agentic-CLI-AKS/)** — > ⚠️ **Preview Feature** - This is an experimental Azure CLI extension currently in preview. Not recommended for production environments.
  - 📄 README: Yes | 📁 Files: 26
- **[BYO-CNI-AKS](./BYO-CNI-AKS/)** — Deploy an AKS cluster using **Bring Your Own CNI (BYO CNI)** and install **Cilium** as the Container Network Interface. This demo includes Bicep infrastructure-as-code, automated deployment scripts, and sample applications with Cilium network policies.
  - 📄 README: Yes | 📁 Files: 23
- **[Custom-AKS-Copilot-Agent](./Custom-AKS-Copilot-Agent/)** — A custom GitHub Copilot agent specialized in Azure Kubernetes Service (AKS) and Kubernetes troubleshooting. This agent acts as an expert SRE to help you diagnose, troubleshoot, and resolve incidents quickly.
  - 📄 README: Yes | 📁 Files: 5
- **[Platform-Enginering-AKS-ArgoCD-ASO](./Platform-Enginering-AKS-ArgoCD-ASO/)** — No description available
  - 📄 README: No | 📁 Files: 0

### Docker

- **[Docker-Hardened-Images](./Docker-Hardened-Images/)** — Welcome to this comprehensive demo on **Docker Hardened Images**! This repository demonstrates Docker's official hardened image solution and best practices for creating secure, production-ready container images.
  - 📄 README: Yes | 📁 Files: 16
- **[Docker-Offload](./Docker-Offload/)** — > **Demonstrating Docker's new cloud execution feature for building and running containers**
  - 📄 README: Yes | 📁 Files: 9
- **[Docker-Sandboxes-Demo](./Docker-Sandboxes-Demo/)** — > **Experimental Feature** - Requires Docker Desktop 4.50 or later
  - 📄 README: Yes | 📁 Files: 10
- **[Docker-Scout](./Docker-Scout/)** — Detect and remediate vulnerabilities in your container images with Docker Scout.
  - 📄 README: Yes | 📁 Files: 30

### Azure

- **[ACR-Task](./ACR-Task/)** — Build container images directly in Azure without needing Docker installed locally.
  - 📄 README: Yes | 📁 Files: 5

### Other

- **[Azure-Copilot-AKS-Troubleshooting](./Azure-Copilot-AKS-Troubleshooting/)** — This demo shows how to use **Microsoft Copilot in Azure** (Azure Portal Copilot) to troubleshoot common issues in Azure Kubernetes Service (AKS) clusters. Instead of manually running `kubectl` commands and digging through logs, you can ask Copilot natural language questions directly in the Azure Portal and get actionable insights.
  - 📄 README: Yes | 📁 Files: 16
- **[Azure-Private-Link-Demo](./Azure-Private-Link-Demo/)** — No description available
  - 📄 README: No | 📁 Files: 0
- **[Falco-AKS-Sentinel](./Falco-AKS-Sentinel/)** — This repository contains the complete Infrastructure as Code (IaC) and configuration for demonstrating Falco runtime security on Azure Kubernetes Service (AKS) with Azure Sentinel integration.
  - 📄 README: Yes | 📁 Files: 18
- **[K6-Load-Testing-Demo](./K6-Load-Testing-Demo/)** — No description available
  - 📄 README: No | 📁 Files: 0
- **[Kyverno-Policy-Demo](./Kyverno-Policy-Demo/)** — No description available
  - 📄 README: No | 📁 Files: 11
- **[VCluster-Demo](./VCluster-Demo/)** — No description available
  - 📄 README: No | 📁 Files: 1
- **[plan](./plan/)** — No description available
  - 📄 README: No | 📁 Files: 0

---

## 🛠️ Prerequisites

### General Requirements
- **Azure CLI** (latest version)
- **kubectl** (v1.28+)
- **Docker Desktop** (v4.27+ for basic, v4.50+ for sandboxes)
- **Azure Subscription** with appropriate permissions

### Optional Tools
- **Bicep CLI** (for template editing)
- **cosign** (for signature verification)
- **Helm** (for chart deployments)

## 🚀 Getting Started

1. **Clone the repository:**
   ```bash
   git clone https://github.com/kasunsjc/Code-Snippets.git
   cd Code-Snippets
   ```

2. **Navigate to a demo folder:**
   ```bash
   cd <example-folder>
   ```

3. **Follow the README or scripts in each folder**

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests to improve these demos.

## 📄 License

This repository is provided for educational purposes. See the [LICENSE](./LICENSE) file for details.

---

<!-- AUTO-GENERATED CONTENT ABOVE - DO NOT EDIT MANUALLY -->
