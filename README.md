# Code Snippets Repository 🚀

Welcome to the **Code Snippets Repository**! This repository contains sample code, demos, and tutorials for Azure Kubernetes Service (AKS), Docker, and container technologies. Perfect for learning, blog posts, and YouTube tutorials.

<!-- AUTO-GENERATED CONTENT BELOW - DO NOT EDIT MANUALLY -->
<!-- Last updated by GitHub Actions -->

> **21 examples** | Kubernetes: 14 | Docker: 4 | Azure: 1 | *Last Updated: September 2026*

## 📋 Table of Contents

| # | Demo | Description | Category |
|---|------|-------------|----------|
| 1 | [ACR-Task](./ACR-Task/) | Build container images directly in Azure without needing Docker installed locally. | Azure |
| 2 | [AKS-ACNS-Cilium-Terraform](./AKS-ACNS-Cilium-Terraform/) | Deep network traffic visibility and security on Azure Kubernetes Service using **Advanced Contain... | Kubernetes |
| 3 | [AKS-AppGW-Containers](./AKS-AppGW-Containers/) | Deploy an AKS cluster using **Application Gateway for Containers** — the next generation of Azure... | Kubernetes |
| 4 | [AKS-ArgoCD-Extension](./AKS-ArgoCD-Extension/) | End-to-end Terraform automation that deploys [Argo CD](https://argo-cd.readthedocs.io/) on Azure ... | Kubernetes |
| 5 | [AKS-Desktop](./AKS-Desktop/) | This demo shows how **AKS Desktop** works and how to use **Azure Managed Projects** to deploy and... | Kubernetes |
| 6 | [AKS-Fleet-Manager-Demo](./AKS-Fleet-Manager-Demo/) | A comprehensive demonstration of Azure Kubernetes Service (AKS) Fleet Manager capabilities, showc... | Kubernetes |
| 7 | [AKS-Istio-Gateway-API](./AKS-Istio-Gateway-API/) | > **Blog Reference:** [Announcing Gateway API support for App Routing (preview) — AKS Blog, March... | Kubernetes |
| 8 | [AKS-KEDA-Demo](./AKS-KEDA-Demo/) | A hands-on demo showing how **KEDA (Kubernetes Event-Driven Autoscaling)** works on | Kubernetes |
| 9 | [AKS-Monitoring](./AKS-Monitoring/) | This guide provides an overview of how to monitor Azure Kubernetes Service (AKS) using Azure Moni... | Kubernetes |
| 10 | [AKS-Nginx-Add-on](./AKS-Nginx-Add-on/) | Deploy the NGINX Ingress Controller as a native AKS add-on with SSL/TLS termination support. | Kubernetes |
| 11 | [AKS-Node-Autoprovision](./AKS-Node-Autoprovision/) | Automatically provision AKS nodes based on workload requirements without managing node pools manu... | Kubernetes |
| 12 | [AKS-NodeRG-Lockdown](./AKS-NodeRG-Lockdown/) | Enhance AKS security by restricting access to node resource group resources. | Kubernetes |
| 13 | [Agentic-CLI-AKS](./Agentic-CLI-AKS/) | > ⚠️ **Preview Feature** - This is an experimental Azure CLI extension currently in preview. Not ... | Kubernetes |
| 14 | [Azure-Copilot-AKS-Troubleshooting](./Azure-Copilot-AKS-Troubleshooting/) | This demo shows how to use **Microsoft Copilot in Azure** (Azure Portal Copilot) to troubleshoot ... | Other |
| 15 | [BYO-CNI-AKS](./BYO-CNI-AKS/) | Deploy an AKS cluster using **Bring Your Own CNI (BYO CNI)** and install **Cilium** as the Contai... | Kubernetes |
| 16 | [Custom-AKS-Copilot-Agent](./Custom-AKS-Copilot-Agent/) | A custom GitHub Copilot agent specialized in Azure Kubernetes Service (AKS) and Kubernetes troubl... | Kubernetes |
| 17 | [Docker-Hardened-Images](./Docker-Hardened-Images/) | Welcome to this comprehensive demo on **Docker Hardened Images**! This repository demonstrates Do... | Docker |
| 18 | [Docker-Offload](./Docker-Offload/) | > **Demonstrating Docker's new cloud execution feature for building and running containers** | Docker |
| 19 | [Docker-Sandboxes-Demo](./Docker-Sandboxes-Demo/) | > **Experimental Feature** - Requires Docker Desktop 4.50 or later | Docker |
| 20 | [Docker-Scout](./Docker-Scout/) | Detect and remediate vulnerabilities in your container images with Docker Scout. | Docker |
| 21 | [Falco-AKS-Sentinel](./Falco-AKS-Sentinel/) | This repository contains the complete Infrastructure as Code (IaC) and configuration for demonstr... | Other |

---

## 📁 Examples by Category

### Kubernetes

- **[AKS-ACNS-Cilium-Terraform](./AKS-ACNS-Cilium-Terraform/)** — Deep network traffic visibility and security on Azure Kubernetes Service using **Advanced Container Networking Services** with **Azure CNI Powered by Cilium**, provisioned entirely with **Terraform**.
  - 📄 README: Yes | 📁 Files: 20
- **[AKS-AppGW-Containers](./AKS-AppGW-Containers/)** — Deploy an AKS cluster using **Application Gateway for Containers** — the next generation of Azure Application Gateway designed for Kubernetes workloads. This demo uses the **Gateway API** (the successor to Ingress) with the ALB Controller AKS add-on.
  - 📄 README: Yes | 📁 Files: 22
- **[AKS-ArgoCD-Extension](./AKS-ArgoCD-Extension/)** — End-to-end Terraform automation that deploys [Argo CD](https://argo-cd.readthedocs.io/) on Azure Kubernetes Service (AKS) using the **`Microsoft.ArgoCD` cluster extension**, with Microsoft Entra ID single sign-on, group-based RBAC, TLS from Azure Key Vault, and automatic DNS via the App Routing add-on — all in a single `./deploy.sh` invocation.
  - 📄 README: Yes | 📁 Files: 25
- **[AKS-Desktop](./AKS-Desktop/)** — This demo shows how **AKS Desktop** works and how to use **Azure Managed Projects** to deploy and manage applications. We use an **AKS Automatic** cluster because Managed Projects only work with AKS Automatic.
  - 📄 README: Yes | 📁 Files: 8
- **[AKS-Fleet-Manager-Demo](./AKS-Fleet-Manager-Demo/)** — A comprehensive demonstration of Azure Kubernetes Service (AKS) Fleet Manager capabilities, showcasing multi-cluster orchestration, resource propagation, and centralized management.
  - 📄 README: Yes | 📁 Files: 21
- **[AKS-Istio-Gateway-API](./AKS-Istio-Gateway-API/)** — > **Blog Reference:** [Announcing Gateway API support for App Routing (preview) — AKS Blog, March 2026](https://blog.aks.azure.com/2026/03/18/app-routing-gateway-api)
  - 📄 README: Yes | 📁 Files: 10
- **[AKS-KEDA-Demo](./AKS-KEDA-Demo/)** — A hands-on demo showing how **KEDA (Kubernetes Event-Driven Autoscaling)** works on
  - 📄 README: Yes | 📁 Files: 72
- **[AKS-Monitoring](./AKS-Monitoring/)** — This guide provides an overview of how to monitor Azure Kubernetes Service (AKS) using Azure Monitor, integrate with Azure Managed Grafana, and set up Azure Alerts with Azure Monitor recording and alert rules.
  - 📄 README: Yes | 📁 Files: 3
- **[AKS-Nginx-Add-on](./AKS-Nginx-Add-on/)** — Deploy the NGINX Ingress Controller as a native AKS add-on with SSL/TLS termination support.
  - 📄 README: Yes | 📁 Files: 8
- **[AKS-Node-Autoprovision](./AKS-Node-Autoprovision/)** — Automatically provision AKS nodes based on workload requirements without managing node pools manually.
  - 📄 README: Yes | 📁 Files: 4
- **[AKS-NodeRG-Lockdown](./AKS-NodeRG-Lockdown/)** — Enhance AKS security by restricting access to node resource group resources.
  - 📄 README: Yes | 📁 Files: 2
- **[Agentic-CLI-AKS](./Agentic-CLI-AKS/)** — > ⚠️ **Preview Feature** - This is an experimental Azure CLI extension currently in preview. Not recommended for production environments.
  - 📄 README: Yes | 📁 Files: 25
- **[BYO-CNI-AKS](./BYO-CNI-AKS/)** — Deploy an AKS cluster using **Bring Your Own CNI (BYO CNI)** and install **Cilium** as the Container Network Interface. This demo includes Bicep infrastructure-as-code, automated deployment scripts, and sample applications with Cilium network policies.
  - 📄 README: Yes | 📁 Files: 22
- **[Custom-AKS-Copilot-Agent](./Custom-AKS-Copilot-Agent/)** — A custom GitHub Copilot agent specialized in Azure Kubernetes Service (AKS) and Kubernetes troubleshooting. This agent acts as an expert SRE to help you diagnose, troubleshoot, and resolve incidents quickly.
  - 📄 README: Yes | 📁 Files: 5

### Docker

- **[Docker-Hardened-Images](./Docker-Hardened-Images/)** — Welcome to this comprehensive demo on **Docker Hardened Images**! This repository demonstrates Docker's official hardened image solution and best practices for creating secure, production-ready container images.
  - 📄 README: Yes | 📁 Files: 15
- **[Docker-Offload](./Docker-Offload/)** — > **Demonstrating Docker's new cloud execution feature for building and running containers**
  - 📄 README: Yes | 📁 Files: 9
- **[Docker-Sandboxes-Demo](./Docker-Sandboxes-Demo/)** — > **Experimental Feature** - Requires Docker Desktop 4.50 or later
  - 📄 README: Yes | 📁 Files: 10
- **[Docker-Scout](./Docker-Scout/)** — Detect and remediate vulnerabilities in your container images with Docker Scout.
  - 📄 README: Yes | 📁 Files: 29

### Azure

- **[ACR-Task](./ACR-Task/)** — Build container images directly in Azure without needing Docker installed locally.
  - 📄 README: Yes | 📁 Files: 5

### Other

- **[Azure-Copilot-AKS-Troubleshooting](./Azure-Copilot-AKS-Troubleshooting/)** — This demo shows how to use **Microsoft Copilot in Azure** (Azure Portal Copilot) to troubleshoot common issues in Azure Kubernetes Service (AKS) clusters. Instead of manually running `kubectl` commands and digging through logs, you can ask Copilot natural language questions directly in the Azure Portal and get actionable insights.
  - 📄 README: Yes | 📁 Files: 16
- **[Falco-AKS-Sentinel](./Falco-AKS-Sentinel/)** — This repository contains the complete Infrastructure as Code (IaC) and configuration for demonstrating Falco runtime security on Azure Kubernetes Service (AKS) with Azure Sentinel integration.
  - 📄 README: Yes | 📁 Files: 17

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
