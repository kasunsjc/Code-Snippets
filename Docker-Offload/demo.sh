#!/bin/bash

###############################################################################
# Docker Offload Demo Script
# This script demonstrates the workflow of using Docker Offload
###############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Docker Offload Demo Workflow           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# Function to print section headers
print_section() {
    echo ""
    echo -e "${GREEN}==>${NC} ${YELLOW}$1${NC}"
    echo ""
}

# Function to run command with explanation
run_command() {
    local explanation=$1
    local command=$2
    
    echo -e "${YELLOW}📌 $explanation${NC}"
    echo -e "${BLUE}$ $command${NC}"
    eval $command
    echo ""
}

# Check prerequisites
print_section "Step 1: Checking Prerequisites"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker is installed"

# Check Docker Desktop version
DOCKER_VERSION=$(docker version --format '{{.Client.Version}}' 2>/dev/null || echo "unknown")
echo -e "${GREEN}✓${NC} Docker version: $DOCKER_VERSION"

# Check if Docker Offload is available
echo ""
echo -e "${YELLOW}To use Docker Offload, you need:${NC}"
echo "  1. Docker Desktop 4.50 or later"
echo "  2. Access to Docker Offload (organization subscription)"
echo "  3. Sign in to Docker Desktop"
echo ""
read -p "Do you have Docker Offload access? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}ℹ️  This demo will work locally. To use Docker Offload:${NC}"
    echo "  - Organization owner must sign up at: https://www.docker.com/products/docker-offload/"
    echo "  - You must be added to the organization"
    echo ""
    USE_OFFLOAD=false
else
    USE_OFFLOAD=true
fi

# Demo workflow
print_section "Step 2: Build the Application"

if [ "$USE_OFFLOAD" = true ]; then
    echo -e "${GREEN}Building with Docker Offload (in the cloud)${NC}"
    echo "This will use cloud resources for the build!"
    echo ""
    
    # Try to start Docker Offload
    echo -e "${YELLOW}📌 Starting Docker Offload${NC}"
    echo -e "${BLUE}$ docker offload start${NC}"
    if docker offload start 2>&1; then
        echo -e "${GREEN}✓${NC} Docker Offload started successfully"
        echo ""
        
        # Verify offload is running
        sleep 2
        if docker offload status &>/dev/null; then
            echo -e "${GREEN}✓${NC} Docker Offload is active"
            echo ""
            
            # Build with offload
            echo -e "${YELLOW}📌 Building image in the cloud${NC}"
            echo -e "${BLUE}$ docker build -t docker-offload-demo:latest --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) .${NC}"
            if docker build -t docker-offload-demo:latest --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) . 2>&1; then
                echo -e "${GREEN}✓${NC} Build completed in the cloud"
            else
                echo -e "${RED}✗${NC} Build failed with offload. Falling back to local build..."
                docker offload stop 2>/dev/null || true
                USE_OFFLOAD=false
                docker build -t docker-offload-demo:latest --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) .
            fi
        else
            echo -e "${RED}✗${NC} Docker Offload didn't start properly. Building locally..."
            USE_OFFLOAD=false
            docker build -t docker-offload-demo:latest --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) .
        fi
    else
        echo -e "${RED}✗${NC} Failed to start Docker Offload"
        echo -e "${YELLOW}Common issues:${NC}"
        echo "  1. Not signed in to Docker Desktop"
        echo "  2. No offload access for your organization"
        echo "  3. Docker Desktop version < 4.50"
        echo ""
        echo -e "${YELLOW}Falling back to local build...${NC}"
        USE_OFFLOAD=false
        docker build -t docker-offload-demo:latest --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) .
    fi
    echo ""
else
    echo -e "${YELLOW}Building locally (without offload)${NC}"
    run_command "Build image locally" "docker build -t docker-offload-demo:latest --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) ."
fi

print_section "Step 3: Run the Application"

if [ "$USE_OFFLOAD" = true ]; then
    echo -e "${GREEN}Running containers in the cloud with Docker Offload${NC}"
    run_command "Run container in cloud" "docker run -d -p 8080:8080 --name offload-demo docker-offload-demo:latest"
else
    echo -e "${YELLOW}Running container locally${NC}"
    run_command "Run container locally" "docker run -d -p 8080:8080 --name offload-demo docker-offload-demo:latest"
fi

print_section "Step 4: Check Container Status"

run_command "List running containers" "docker ps"
run_command "Check container logs" "docker logs offload-demo --tail 20"

print_section "Step 5: Test the Application"

echo "Waiting for application to start..."
sleep 5

echo -e "${YELLOW}Testing endpoints:${NC}"
echo ""

# Test health endpoint
if curl -f http://localhost:8080/health &>/dev/null; then
    echo -e "${GREEN}✓${NC} Health check: PASSED"
    curl -s http://localhost:8080/health | python3 -m json.tool 2>/dev/null || echo ""
else
    echo -e "${RED}✗${NC} Health check: FAILED"
fi

echo ""

# Test info endpoint
echo -e "${YELLOW}System Information:${NC}"
curl -s http://localhost:8080/api/info | python3 -m json.tool 2>/dev/null || echo "Could not fetch info"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Application is running! 🎉         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Access the application:${NC}"
echo "  🌐 Web UI:    http://localhost:8080"
echo "  💚 Health:    http://localhost:8080/health"
echo "  📊 Info:      http://localhost:8080/api/info"
echo "  📋 Build:     http://localhost:8080/api/build-info"
echo ""
echo -e "${YELLOW}Test compute endpoint:${NC}"
echo "  curl -X POST http://localhost:8080/api/process -H 'Content-Type: application/json' -d '{\"iterations\": 1000000}'"
echo ""

if [ "$USE_OFFLOAD" = true ]; then
    echo -e "${YELLOW}Docker Offload Status:${NC}"
    docker offload status 2>/dev/null || echo "  Run: docker offload status"
    echo ""
fi

print_section "Step 6: Monitor Usage"

echo "Container resource usage:"
docker stats offload-demo --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

echo ""
echo -e "${YELLOW}To stop the demo:${NC}"
echo "  docker stop offload-demo && docker rm offload-demo"
echo ""

if [ "$USE_OFFLOAD" = true ]; then
    echo -e "${YELLOW}To stop Docker Offload:${NC}"
    echo "  docker offload stop"
    echo ""
fi

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}Demo Complete!${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
