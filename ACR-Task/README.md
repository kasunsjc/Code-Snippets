# Azure Container Registry Tasks

Build container images directly in Azure without needing Docker installed locally.

## 📋 Overview

Azure Container Registry (ACR) Tasks allows you to build, test, and push container images to your registry using Azure's compute infrastructure. This eliminates the need for local Docker installations and provides consistent, scalable builds.

## 📁 Contents

```
ACR-Task/
├── README.md           # This documentation
├── command.azcli       # Azure CLI commands for ACR Tasks
└── python-app/         # Sample Python application
    ├── Dockerfile      # Container image definition
    ├── app.py          # Python application code
    └── requirements.txt # Python dependencies
```

## 🚀 Prerequisites

- Azure CLI installed and configured
- Azure Container Registry created
- Appropriate permissions to push images

## 💻 Quick Start

### 1. Set Up Environment Variables

```bash
export ACR_NAME=your-acr-name
```

### 2. Build the Image

```bash
cd ACR-Task/python-app
az acr build -t $ACR_NAME.azurecr.io/hello-world:{{.Run.ID}} --registry $ACR_NAME -f ./Dockerfile .
```

The `{{.Run.ID}}` placeholder automatically tags the image with a unique run identifier.

## 🔧 Key Features

- **No Docker Required**: Build images directly in Azure
- **Automatic Tagging**: Use run variables for unique tags
- **Build Triggers**: Automate builds on code or base image changes
- **Multi-Architecture**: Build images for multiple platforms

## 📚 Learn More

- [ACR Tasks Documentation](https://learn.microsoft.com/azure/container-registry/container-registry-tasks-overview)
- [Quick Build Guide](https://learn.microsoft.com/azure/container-registry/container-registry-quick-task-cli)

## 📄 License

This demo is provided for educational purposes.
