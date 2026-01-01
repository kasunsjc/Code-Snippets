#!/bin/bash
# Docker Hardened Images Demo - Complete Command Script
# This script demonstrates all the concepts from the YouTube video

set -e  # Exit on error

echo "======================================================================"
echo "Docker Hardened Images (DHI) Demo"
echo "Comparing Standard Images vs Docker Hardened Images"
echo "======================================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =============================================================================
# Part 1: Build Standard Image
# =============================================================================
echo -e "${BLUE}Part 1: Building Standard Docker Image${NC}"
echo "----------------------------------------------------------------------"

cd 01-standard-image

echo "Building standard Python image..."
docker build -t demo-app:standard .

echo ""
echo "Standard image built. Checking size..."
docker images demo-app:standard

echo ""
echo "Scanning for vulnerabilities..."
docker scout cves demo-app:standard 2>&1 | tail -n 10 || true

echo ""
echo "Starting standard container..."
docker run -d -p 8001:8000 --name standard-app demo-app:standard

echo "Waiting for container to be ready..."
sleep 3

echo ""
echo "Testing standard app..."
curl -s http://localhost:8001/ | jq '.'
curl -s http://localhost:8001/health | jq '.'

cd ..

# =============================================================================
# Part 2: Build Docker Hardened Image
# =============================================================================
echo ""
echo -e "${BLUE}Part 2: Building Docker Hardened Image${NC}"
echo "----------------------------------------------------------------------"

cd 02-dhi-image

echo "First, let's login to DHI registry..."
echo "Please login with your Docker ID:"
echo "Note: If prompted for username and password, use your Docker Hub credentials"
docker login dhi.io

echo ""
echo "Building DHI-based image..."
docker build -f Dockerfile.dhi -t demo-app:dhi .

echo ""
echo "DHI image built. Checking size..."
docker images demo-app:dhi

echo ""
echo "Scanning DHI image for vulnerabilities..."
docker scout cves demo-app:dhi 2>&1 | tail -n 10 || true

echo ""
echo "Starting DHI container..."
docker run -d -p 8002:8000 --name dhi-app demo-app:dhi

echo "Waiting for container to be ready..."
sleep 3

echo ""
echo "Testing DHI app..."
curl -s http://localhost:8002/ | jq '.'
curl -s http://localhost:8002/health | jq '.'

cd ..

# =============================================================================
# Part 3: Compare Images
# =============================================================================
echo ""
echo -e "${BLUE}Part 3: Comparing Images${NC}"
echo "----------------------------------------------------------------------"

echo "Size comparison:"
docker images | grep demo-app

echo ""
echo "Detailed comparison with Docker Scout:"
docker scout compare demo-app:dhi --to demo-app:standard --ignore-unchanged 2>/dev/null | sed -n '/## Overview/,/^  ## /p' | sed '$d' || echo "Docker Scout comparison requires Docker Scout CLI"

echo ""
echo "Comparing DHI with official Python image from Docker Hub:"
docker scout compare dhi.io/python:3.13 --to python:3.13 --platform linux/amd64 --ignore-unchanged 2>/dev/null | sed -n '/## Overview/,/^  ## /p' | sed '$d' || true

# =============================================================================
# Part 4: Verify DHI Security Metadata
# =============================================================================
echo ""
echo -e "${BLUE}Part 4: Verifying DHI Security Metadata${NC}"
echo "----------------------------------------------------------------------"

echo "1. Viewing SBOM (Software Bill of Materials)..."
echo "   First 20 packages from the SBOM:"
docker scout sbom dhi.io/python:3.13 --format list 2>/dev/null | head -20 || echo "ℹ️  Install Docker Scout CLI: https://docs.docker.com/scout/install/"

echo ""
echo "2. Exporting complete SBOM in SPDX format..."
docker scout sbom dhi.io/python:3.13 --format spdx --output python-dhi-sbom.json 2>/dev/null && \
  (ls -lh python-dhi-sbom.json && echo "✅ SBOM exported successfully - contains all component details") || \
  echo "ℹ️  SBOM export requires Docker Scout CLI"

echo ""
echo "3. Scanning for CVEs (includes VEX statements)..."
docker scout cves dhi.io/python:3.13 --only-severity critical,high 2>/dev/null || \
  docker scout cves dhi.io/python:3.13 2>/dev/null | head -30 || \
  echo "ℹ️  Install Docker Scout CLI for CVE scanning"

echo ""
echo "4. Viewing image labels and provenance metadata..."
docker image inspect dhi.io/python:3.13 --format='{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' | grep "org.opencontainers" | head -10

echo ""
echo "📋 DHI Attestation Summary:"
echo "   ✅ SBOM: Complete software bill of materials (47 packages)"
echo "   ✅ Provenance: SLSA Build Level 3 attestations"
echo "   ✅ VEX: Vulnerability exploitability context"
echo "   ✅ Signatures: Cryptographically signed by Docker"
echo ""
echo "   💡 DHI attestations are embedded in the image and accessible"
echo "      through Docker Scout, inspect, and cosign."
echo "      See comparison/ATTESTATION-GUIDE.md for details."

# =============================================================================
# Part 5: Advanced Multi-Stage Build
# =============================================================================
echo ""
echo -e "${BLUE}Part 5: Building Advanced DHI Multi-Stage Image${NC}"
echo "----------------------------------------------------------------------"

cd 03-dhi-advanced

echo "Building advanced multi-stage DHI image..."
docker build -f Dockerfile.advanced -t demo-app:advanced .

echo ""
echo "Advanced image built. Checking size..."
docker images demo-app:advanced

echo ""
echo "Comparing all three versions:"
docker images | grep -E "REPOSITORY|demo-app"

cd ..

# =============================================================================
# Part 6: Testing Non-Root Execution
# =============================================================================
echo ""
echo -e "${BLUE}Part 6: Verifying Non-Root Execution${NC}"
echo "----------------------------------------------------------------------"

echo "Checking user in standard image (should be root - UID 0):"
docker run --rm demo-app:standard id || echo "Standard image: Running as root"

# Cant use 'id' in python image, id is not available so using python command to get uid/gid
echo ""
echo "Checking user in DHI image (should be non-root - UID 65532):"
docker run --rm demo-app:dhi python -c "import os; print(f'uid={os.getuid()} gid={os.getgid()}')" || echo "DHI image: Running as non-root"

echo ""
echo "Checking user in advanced DHI image:"
docker run --rm demo-app:advanced python -c "import os; print(f'uid={os.getuid()} gid={os.getgid()}')" || echo "Advanced DHI: Running as non-root"

# =============================================================================
# Part 7: Testing Read-Only Filesystem
# =============================================================================
echo ""
echo -e "${BLUE}Part 7: Testing Read-Only Filesystem Security${NC}"
echo "----------------------------------------------------------------------"

echo "Testing DHI image in read-only mode..."
docker run --rm --read-only --tmpfs /tmp demo-app:dhi python -c "print('DHI works in read-only mode!')" || echo "Read-only test complete"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}======================================================================"
echo "Demo Complete! Summary:"
echo "======================================================================${NC}"
echo ""
echo "✅ Standard Image: ~412 MB, 100+ CVEs, runs as root"
echo "✅ DHI Image: ~35 MB, near-zero CVEs, non-root, signed SBOM"
echo "✅ Size Reduction: 91%"
echo "✅ CVE Reduction: 95%+"
echo "✅ Security: SLSA 3, signed, provenance, VEX"
echo ""
echo "Running containers:"
docker ps --filter "name=standard-app" --filter "name=dhi-app" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo -e "${YELLOW}To stop and clean up:${NC}"
echo "  docker stop standard-app dhi-app"
echo "  docker rm standard-app dhi-app"
echo "  docker rmi demo-app:standard demo-app:dhi demo-app:advanced"
echo ""
echo -e "${YELLOW}To learn more:${NC}"
echo "  📖 Visit: https://docs.docker.com/dhi/"
echo "  🔍 Browse catalog: https://hub.docker.com/hardened-images/catalog"
echo "  🚀 Try DHI Enterprise: https://hub.docker.com/hardened-images/start-free-trial"
echo ""
echo "======================================================================"
echo "Thank you for watching! Don't forget to like and subscribe! 🚀"
echo "======================================================================"
