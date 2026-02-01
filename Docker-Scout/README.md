# Docker Scout Demo

Detect and remediate vulnerabilities in your container images with Docker Scout.

## 📋 Overview

Docker Scout is a security tool that analyzes container images to identify vulnerabilities, provide remediation recommendations, and help you understand your software supply chain.

## 📁 Contents

```
Docker-Scout/
├── README.md              # This documentation
├── commands.ps1           # PowerShell commands for scanning
├── bicep-templates/       # Azure infrastructure templates
│   ├── acr.bicep          # Azure Container Registry deployment
│   ├── acr.bicepparam     # Deployment parameters
│   └── commands.azcli     # Azure CLI commands
├── sample-python-app/     # Sample application with vulnerabilities
│   ├── Dockerfile         # Container image definition
│   ├── src/               # Application source code
│   ├── requirements.txt   # Python dependencies
│   ├── docker-compose.yml # Compose configuration
│   └── README.md          # App documentation
└── scout-demo-service/    # Demo service examples
```

## 🚀 Quick Start

### 1. Build Sample Application

```bash
cd sample-python-app
docker build -t scout-demo .
```

### 2. Scan for Vulnerabilities

```bash
# Quick CVE scan
docker scout cves scout-demo

# Detailed scan with recommendations
docker scout cves scout-demo --only-severity critical,high

# Generate SBOM
docker scout sbom scout-demo
```

### 3. Get Remediation Recommendations

```bash
docker scout recommendations scout-demo
```

## 🔧 Key Features

### Vulnerability Detection
- Scan local images, registries, and running containers
- Identify CVEs across all image layers
- Filter by severity (critical, high, medium, low)

### Software Bill of Materials (SBOM)
- Complete inventory of all packages
- Dependency relationships
- License information
- Export to SPDX/CycloneDX formats

### Remediation Guidance
- Actionable fix recommendations
- Base image upgrade suggestions
- Package update guidance

### Policy Enforcement
- Custom security policies
- CI/CD integration
- Compliance checks

## 💻 Commands Reference

### Basic Scanning

```bash
# Scan local image
docker scout cves <image-name>

# Scan image in registry
docker scout cves registry.example.com/image:tag

# Scan with specific platform
docker scout cves <image-name> --platform linux/amd64
```

### SBOM Operations

```bash
# Generate SBOM
docker scout sbom <image-name>

# Export as SPDX
docker scout sbom <image-name> --format spdx > sbom.spdx.json

# Export as CycloneDX
docker scout sbom <image-name> --format cyclonedx > sbom.cdx.json
```

### Compare Images

```bash
# Compare two images
docker scout compare <new-image> --to <old-image>

# Compare with base image
docker scout compare <image> --to-latest
```

### Policy and Compliance

```bash
# Check policies
docker scout policy <image-name>

# View organization policies
docker scout policy --org <organization>
```

## 🏗️ Azure Integration

Deploy Azure Container Registry with scanning integration:

```bash
cd bicep-templates

# Create resource group
az group create --name scout-demo-rg --location eastus

# Deploy ACR
az deployment group create \
  --resource-group scout-demo-rg \
  --template-file acr.bicep \
  --parameters acr.bicepparam
```

## 💡 Best Practices

1. **Scan Early and Often**: Integrate scanning in CI/CD pipelines
2. **Prioritize Fixes**: Focus on critical and high severity vulnerabilities
3. **Use Official Base Images**: Start with verified, maintained base images
4. **Keep Updated**: Regularly update base images and dependencies
5. **Track SBOM**: Maintain software inventory for compliance

## 📊 Sample Output

```
## Overview

                    │          Analyzed Image
────────────────────┼──────────────────────────────
  Target            │  scout-demo:latest
    digest          │  sha256:abc123...
    platform        │  linux/amd64
    vulnerabilities │    2C    8H   12M   25L
    size            │  125 MB
    packages        │  230
```

## 🔗 CI/CD Integration

### GitHub Actions

```yaml
- name: Analyze image
  uses: docker/scout-action@v1
  with:
    command: cves
    image: ${{ env.IMAGE_NAME }}
    only-severities: critical,high
```

### GitLab CI

```yaml
security_scan:
  image: docker:latest
  script:
    - docker scout cves $IMAGE_NAME --exit-code
```

## 📚 Learn More

- [Docker Scout Documentation](https://docs.docker.com/scout/)
- [Docker Scout CLI Reference](https://docs.docker.com/reference/cli/docker/scout/)
- [Integrations Guide](https://docs.docker.com/scout/integrations/)

## 📄 License

This demo is provided for educational purposes.
