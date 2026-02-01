# Code Snippets Repository 🚀

Welcome to the **Code Snippets Repository**! This repository contains sample code, demos, and tutorials for Azure Kubernetes Service (AKS), Docker, and container technologies. Perfect for learning, blog posts, and YouTube tutorials.

## 📋 Table of Contents

| Demo | Description | Category |
|------|-------------|----------|
| [ACR-Task](#acr-task) | Azure Container Registry Tasks for automated image builds | Azure |
| [AKS-Fleet-Manager-Demo](#aks-fleet-manager-demo) | Multi-cluster orchestration with AKS Fleet Manager | Kubernetes |
| [AKS-Monitoring](#aks-monitoring) | Azure Monitor integration with AKS and Grafana | Monitoring |
| [AKS-Nginx-Add-on](#aks-nginx-add-on) | NGINX Ingress Controller as AKS add-on with SSL/TLS | Kubernetes |
| [AKS-Node-Autoprovision](#aks-node-autoprovision) | Automatic node provisioning for AKS workloads | Kubernetes |
| [AKS-NodeRG-Lockdown](#aks-noderg-lockdown) | Node Resource Group lockdown for AKS security | Security |
| [Agentic-CLI-AKS](#agentic-cli-aks) | AI-powered troubleshooting CLI for AKS | AI/ML |
| [Docker-Hardened-Images](#docker-hardened-images) | Docker's official hardened image solution | Docker |
| [Docker-Sandboxes-Demo](#docker-sandboxes-demo) | Isolated environments for AI agents with Docker | Docker |
| [Docker-Scout](#docker-scout) | Container vulnerability scanning with Docker Scout | Security |

---

## 📁 Demo Contents

### ACR-Task

**Azure Container Registry Tasks** - Automate container image builds directly in Azure.

📂 **Location:** [`ACR-Task/`](./ACR-Task/)

**What's Included:**
- Azure CLI commands for ACR Task builds
- Sample Python application with Dockerfile
- Automated build pipeline examples

**Key Features:**
- Build images without local Docker
- Automatic image tagging with run IDs
- Integration with Azure DevOps/GitHub Actions

**Quick Start:**
```bash
cd ACR-Task
export ACR_NAME=your-acr-name
az acr build -t $ACR_NAME.azurecr.io/hello-world:{{.Run.ID}} --registry $ACR_NAME -f ./Dockerfile .
```

---

### AKS-Fleet-Manager-Demo

**Multi-Cluster Orchestration** - Manage multiple AKS clusters as a single fleet.

📂 **Location:** [`AKS-Fleet-Manager-Demo/`](./AKS-Fleet-Manager-Demo/)

**What's Included:**
- Complete Bicep templates for Fleet Manager deployment
- Kubernetes manifests for resource propagation
- Multi-cluster service examples
- Deployment and cleanup scripts

**Key Features:**
- Deploy applications across multiple clusters from a single point
- Resource placement policies (PickAll, PickN, PickFixed)
- Multi-cluster service discovery
- Update orchestration across fleet members

**Quick Start:**
```bash
cd AKS-Fleet-Manager-Demo
./deploy.sh              # Deploy infrastructure
./deploy-samples.sh      # Deploy sample applications
./cleanup.sh             # Clean up resources
```

📚 [Full Documentation](./AKS-Fleet-Manager-Demo/README.md)

---

### AKS-Monitoring

**Azure Monitor for AKS** - Monitor your AKS clusters with Azure Monitor and Grafana.

📂 **Location:** [`AKS-Monitoring/`](./AKS-Monitoring/)

**What's Included:**
- Bicep templates for monitoring infrastructure
- Azure Monitor workspace configuration
- Managed Grafana integration
- Alert rules setup

**Key Features:**
- Container Insights integration
- Prometheus metrics collection
- Custom Grafana dashboards
- Azure Alerts with recording rules

**Quick Start:**
```bash
cd AKS-Monitoring
az group create --name aks-mon-rg --location northeurope
az deployment group create --resource-group aks-mon-rg --template-file aks-monitoring.bicep
```

📚 [Full Documentation](./AKS-Monitoring/README.md)

---

### AKS-Nginx-Add-on

**NGINX Ingress as AKS Add-on** - Application routing with NGINX and SSL/TLS termination.

📂 **Location:** [`AKS-Nginx-Add-on/`](./AKS-Nginx-Add-on/)

**What's Included:**
- **Create-AKS-Nginx-Add-On/** - Basic NGINX add-on setup
- **SSL-With-KeyVault-AzureDNS/** - SSL termination with Azure Key Vault and DNS integration
- Sample applications and ingress configurations

**Key Features:**
- Native AKS app routing add-on
- SSL/TLS certificate management with Key Vault
- Azure DNS zone integration
- Simple deployment without Helm

**Quick Start:**
```bash
cd AKS-Nginx-Add-on/Create-AKS-Nginx-Add-On
./commands.sh  # Creates AKS with NGINX add-on and deploys sample app
```

---

### AKS-Node-Autoprovision

**Node Autoprovisioning** - Automatically provision nodes based on workload demands.

📂 **Location:** [`AKS-Node-Autoprovision/`](./AKS-Node-Autoprovision/)

**What's Included:**
- Azure CLI commands for enabling autoprovisioning
- Node pool YAML configurations
- Sample deployment manifests

**Key Features:**
- Automatic node scaling based on pod requirements
- Cost optimization through efficient resource utilization
- Support for various VM sizes and configurations
- Preview feature configuration steps

**Quick Start:**
```bash
cd AKS-Node-Autoprovision
# Follow commands.azcli to enable and configure autoprovisioning
```

---

### AKS-NodeRG-Lockdown

**Node Resource Group Lockdown** - Secure your AKS infrastructure by restricting access to node resources.

📂 **Location:** [`AKS-NodeRG-Lockdown/`](./AKS-NodeRG-Lockdown/)

**What's Included:**
- Azure CLI commands for NRG lockdown configuration
- Comparison between default and locked-down clusters
- Feature registration steps

**Key Features:**
- ReadOnly restriction on node resource groups
- Prevent unauthorized modifications to AKS infrastructure
- Enhanced security compliance
- Preview feature setup

**Quick Start:**
```bash
cd AKS-NodeRG-Lockdown
./commands.sh  # Creates clusters with and without lockdown for comparison
```

---

### Agentic-CLI-AKS

**AI-Powered AKS Troubleshooting** - Use natural language to diagnose and troubleshoot AKS clusters.

📂 **Location:** [`Agentic-CLI-AKS/`](./Agentic-CLI-AKS/)

**What's Included:**
- Complete Bicep templates for infrastructure deployment
- Sample applications with intentional issues for testing
- Deployment and cleanup scripts
- Comprehensive troubleshooting examples

**Key Features:**
- Natural language queries for cluster diagnostics
- Integration with Azure OpenAI (GPT-4o)
- Interactive troubleshooting sessions
- Multi-source intelligence (K8s APIs, logs, metrics)

**Quick Start:**
```bash
cd Agentic-CLI-AKS
./deploy.sh                      # Deploy AKS and Azure OpenAI
az extension add --name aks-agent  # Install extension
az aks agent-init                # Configure LLM
az aks agent "What's wrong with my cluster?"
```

📚 [Full Documentation](./Agentic-CLI-AKS/README.md)

---

### Docker-Hardened-Images

**Docker Hardened Images (DHI)** - Minimal, secure, production-ready container images.

📂 **Location:** [`Docker-Hardened-Images/`](./Docker-Hardened-Images/)

**What's Included:**
- Standard vs DHI image comparison
- Multi-stage build examples
- Security scanning demos
- SBOM and provenance verification

**Key Features:**
- 95% fewer vulnerabilities (near-zero CVEs)
- 90% smaller image sizes
- SLSA Build Level 3 provenance
- Signed SBOMs and VEX statements
- Non-root execution by default

**Quick Start:**
```bash
cd Docker-Hardened-Images
# Build and compare standard vs DHI images
docker build -t demo-app:standard ./01-standard-image
docker build -f ./02-dhi-image/Dockerfile.dhi -t demo-app:dhi ./02-dhi-image
docker scout compare demo-app:dhi --to demo-app:standard
```

📚 [Full Documentation](./Docker-Hardened-Images/README.md)

---

### Docker-Sandboxes-Demo

**Docker Sandboxes** - Isolated environments for running AI agents securely.

📂 **Location:** [`Docker-Sandboxes-Demo/`](./Docker-Sandboxes-Demo/)

**What's Included:**
- Sandbox configuration examples
- Custom template Dockerfiles
- Usage examples for various workflows
- Best practices for security

**Key Features:**
- Isolated AI agent execution
- Persistent state across sessions
- Git integration
- Docker socket access (optional)

**Prerequisites:** Docker Desktop 4.50+

**Quick Start:**
```bash
cd Docker-Sandboxes-Demo
docker sandbox run claude  # Run Claude in isolated sandbox
docker sandbox ls          # List active sandboxes
```

📚 [Full Documentation](./Docker-Sandboxes-Demo/README.md)

---

### Docker-Scout

**Docker Scout** - Container image vulnerability scanning and analysis.

📂 **Location:** [`Docker-Scout/`](./Docker-Scout/)

**What's Included:**
- Sample Python application with vulnerabilities
- Bicep templates for Azure Container Registry
- PowerShell commands for scanning
- Scout demo service examples

**Key Features:**
- Vulnerability detection and remediation
- SBOM generation
- Policy enforcement
- CI/CD integration

**Quick Start:**
```bash
cd Docker-Scout
# Build and scan sample application
docker build -t scout-demo ./sample-python-app
docker scout cves scout-demo
```

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
   cd AKS-Fleet-Manager-Demo
   ```

3. **Follow the README or scripts in each folder**

## 📚 Categories

### By Technology
| Category | Demos |
|----------|-------|
| **Azure Kubernetes Service** | AKS-Fleet-Manager, AKS-Monitoring, AKS-Nginx-Add-on, AKS-Node-Autoprovision, AKS-NodeRG-Lockdown, Agentic-CLI-AKS |
| **Docker** | Docker-Hardened-Images, Docker-Sandboxes-Demo, Docker-Scout |
| **Azure Container Registry** | ACR-Task, Docker-Scout |
| **Security** | Docker-Hardened-Images, AKS-NodeRG-Lockdown, Docker-Scout |
| **AI/ML** | Agentic-CLI-AKS, Docker-Sandboxes-Demo |

### By Complexity
| Level | Demos |
|-------|-------|
| **Beginner** | ACR-Task, AKS-Nginx-Add-on |
| **Intermediate** | AKS-Monitoring, AKS-Node-Autoprovision, Docker-Scout |
| **Advanced** | AKS-Fleet-Manager-Demo, Agentic-CLI-AKS, Docker-Hardened-Images |

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests to improve these demos.

## 📄 License

This repository is provided for educational purposes. See the [LICENSE](./LICENSE) file for details.

---

**Happy Learning! 🎓**

*Last Updated: February 2026*
