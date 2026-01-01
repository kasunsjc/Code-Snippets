# Quick Start Guide - Docker Hardened Images Demo

## 🚀 Get Started in 5 Minutes

### Prerequisites
```bash
# Check Docker is installed
docker --version

# Check Docker Scout (included with Docker Desktop)
docker scout version

# Login to Docker Hardened Images registry
docker login dhi.io
```

### Option 1: Run the Full Demo Script

```bash
# Make the script executable
chmod +x commands.sh

# Run the complete demo
./commands.sh
```

This will:
1. Build standard and DHI images
2. Compare sizes and vulnerabilities
3. Verify security metadata
4. Show you the dramatic differences

### Option 2: Manual Step-by-Step

#### Step 1: Build Standard Image (5 min)
```bash
cd 01-standard-image
docker build -t demo-app:standard .
docker images demo-app:standard
docker scout cves demo-app:standard
cd ..
```

#### Step 2: Build DHI Image (5 min)
```bash
cd 02-dhi-image
docker build -f Dockerfile.dhi -t demo-app:dhi .
docker images demo-app:dhi
docker scout cves demo-app:dhi
cd ..
```

#### Step 3: Compare (1 min)
```bash
# Compare sizes
docker images | grep demo-app

# Compare with Docker Scout
docker scout compare demo-app:dhi --to demo-app:standard
```

#### Step 4: Run and Test (2 min)
```bash
# Start both containers
docker run -d -p 8001:8000 --name standard-app demo-app:standard
docker run -d -p 8002:8000 --name dhi-app demo-app:dhi

# Test them
curl http://localhost:8001/
curl http://localhost:8002/

# Stop and cleanup
docker stop standard-app dhi-app
docker rm standard-app dhi-app
```

## 📊 Expected Results

### Image Size
- **Standard**: ~412 MB
- **DHI**: ~35 MB
- **Savings**: 91% reduction

### Vulnerabilities
- **Standard**: 1 High, 5 Medium, 141 Low (149 total)
- **DHI**: 0 Critical, 0 High, 0 Medium, 0 Low (0 total)
- **Improvement**: 100% CVE reduction

### Packages
- **Standard**: ~610 packages
- **DHI**: ~80 packages
- **Reduction**: 87% fewer packages

## 🔍 Verify DHI Security Features

```bash
# View SBOM
docker scout sbom dhi.io/python:3.13

# View attestations
docker scout attestation dhi.io/python:3.13

# Verify signatures (if cosign installed)
cosign verify dhi.io/python:3.13 \
  --certificate-identity-regexp="https://github.com/docker-hardened-images/*" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

## 🎓 Learn More

- 📖 [Full README](README.md) - Complete documentation
- 📊 [Comparison Report](comparison/comparison-report.md) - Detailed analysis
- 🔗 [Official DHI Docs](https://docs.docker.com/dhi/)
- 🔍 [DHI Catalog](https://hub.docker.com/hardened-images/catalog)

## 🐛 Troubleshooting

### "Cannot connect to DHI registry"
```bash
# Make sure you're logged in
docker login dhi.io
# Use your Docker Hub credentials
```

### "Permission denied"
```bash
# Make script executable
chmod +x commands.sh
```

### "Image not found"
```bash
# Pull the base DHI image manually
docker pull dhi.io/python:3.13
```
**Ready to secure your containers? Let's go! 🚀**
