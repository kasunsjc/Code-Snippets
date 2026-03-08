#!/bin/bash

###############################################################################
# Docker Offload Commands Reference
# Quick reference for all Docker Offload operations
###############################################################################

echo "Docker Offload Commands Reference"
echo "================================="
echo ""

echo "# Prerequisites"
echo "# 1. Docker Desktop 4.50 or later"
echo "# 2. Organization subscribed to Docker Offload"
echo "# 3. Signed in to Docker Desktop"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "DOCKER OFFLOAD MANAGEMENT"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Check Docker Offload status"
echo "docker offload status"
echo ""

echo "# Start Docker Offload (enables cloud execution)"
echo "docker offload start"
echo ""

echo "# Stop Docker Offload (returns to local execution)"
echo "docker offload stop"
echo ""

echo "# View Offload CLI help"
echo "docker offload --help"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "BUILDING WITH DOCKER OFFLOAD"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Build image in the cloud (when offload is started)"
echo "docker offload start"
echo "docker build -t docker-offload-demo:latest ."
echo ""

echo "# Build with build args"
echo "docker build -t docker-offload-demo:latest --build-arg BUILD_DATE=\$(date -u +%Y-%m-%dT%H:%M:%SZ) ."
echo ""

echo "# Build without cache (fresh cloud build)"
echo "docker build --no-cache -t docker-offload-demo:latest ."
echo ""

echo "# Multi-platform build in cloud"
echo "docker buildx build --platform linux/amd64,linux/arm64 -t docker-offload-demo:latest ."
echo ""

echo "═══════════════════════════════════════════════════════"
echo "RUNNING CONTAINERS WITH DOCKER OFFLOAD"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Run container in cloud"
echo "docker offload start"
echo "docker run -d -p 8080:8080 --name demo docker-offload-demo:latest"
echo ""

echo "# Run with environment variables"
echo "docker run -d -p 8080:8080 -e DEPLOYMENT_TYPE='Cloud' --name demo docker-offload-demo:latest"
echo ""

echo "# Run with volume mounts (bind mounts work seamlessly)"
echo "docker run -d -p 8080:8080 -v \$(pwd)/data:/app/data --name demo docker-offload-demo:latest"
echo ""

echo "# Run interactively"
echo "docker run -it --rm docker-offload-demo:latest /bin/bash"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "DOCKER COMPOSE WITH OFFLOAD"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Start multi-container app in cloud"
echo "docker offload start"
echo "docker compose up -d"
echo ""

echo "# View logs"
echo "docker compose logs -f"
echo ""

echo "# Stop services"
echo "docker compose down"
echo ""

echo "# Rebuild and restart"
echo "docker compose up -d --build"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "CONTAINER MANAGEMENT"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# List running containers"
echo "docker ps"
echo ""

echo "# View container logs"
echo "docker logs offload-demo"
echo "docker logs -f offload-demo  # Follow logs"
echo ""

echo "# Execute command in container"
echo "docker exec -it offload-demo /bin/bash"
echo ""

echo "# Inspect container"
echo "docker inspect offload-demo"
echo ""

echo "# View container stats"
echo "docker stats offload-demo"
echo ""

echo "# Stop and remove container"
echo "docker stop offload-demo"
echo "docker rm offload-demo"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "TESTING THE DEMO APPLICATION"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Open in browser"
echo "open http://localhost:8080"
echo ""

echo "# Test health endpoint"
echo "curl http://localhost:8080/health | jq"
echo ""

echo "# Get system info"
echo "curl http://localhost:8080/api/info | jq"
echo ""

echo "# Test compute endpoint"
echo "curl -X POST http://localhost:8080/api/process \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"iterations\": 5000000}' | jq"
echo ""

echo "# Get build information"
echo "curl http://localhost:8080/api/build-info | jq"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "MONITORING & DEBUGGING"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Check Offload session duration (in Docker Desktop footer)"
echo "# Look for hourglass icon when Offload is active"
echo ""

echo "# View detailed session information"
echo "# In Docker Desktop: Offload > Insights"
echo ""

echo "# Monitor system resources"
echo "curl http://localhost:8080/api/info | jq '.resources'"
echo ""

echo "# Stream container logs"
echo "docker logs -f offload-demo"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "CLEANUP"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Stop and remove everything"
echo "docker compose down"
echo "docker stop offload-demo && docker rm offload-demo"
echo "docker rmi docker-offload-demo:latest"
echo ""

echo "# Stop Docker Offload"
echo "docker offload stop"
echo "# Note: Offload auto-idles after ~5 minutes of inactivity"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "COMPARISON: LOCAL VS OFFLOAD"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Build locally"
echo "docker offload stop"
echo "time docker build -t demo:local ."
echo ""

echo "# Build in cloud with offload"
echo "docker offload start"
echo "time docker build -t demo:cloud ."
echo ""

echo "# Compare build times!"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "TROUBLESHOOTING"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Verify offload access"
echo "# 1. Check Docker Desktop header for offload toggle"
echo "# 2. Check Docker Desktop settings"
echo "# 3. Verify organization subscription"
echo ""

echo "# If offload won't start"
echo "docker offload status  # Check current state"
echo "# Sign in to Docker Desktop"
echo "# Select correct organization if member of multiple"
echo ""

echo "# If container won't run"
echo "docker logs offload-demo  # Check logs"
echo "docker ps -a  # Check all containers"
echo "docker inspect offload-demo  # Check configuration"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "ADVANCED USAGE"
echo "═══════════════════════════════════════════════════════"
echo ""

echo "# Configure idle timeout"
echo "# Go to Docker Desktop > Settings > Features > Docker Offload"
echo "# Adjust idle timeout (default: 5 minutes)"
echo ""

echo "# Port forwarding (works automatically with offload)"
echo "docker run -d -p 3000:3000 -p 8080:8080 myapp"
echo ""

echo "# Network creation"
echo "docker network create mynetwork"
echo "docker run -d --network mynetwork --name app1 myapp"
echo ""

echo "# Volume management"
echo "docker volume create mydata"
echo "docker run -d -v mydata:/data myapp"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "USEFUL LINKS"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Documentation: https://docs.docker.com/offload/"
echo "Quickstart: https://docs.docker.com/offload/quickstart/"
echo "Sign up: https://www.docker.com/products/docker-offload/"
echo ""
