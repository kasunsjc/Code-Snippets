#!/bin/bash

# Docker Sandboxes Helper Commands
# Simplifies working with Docker Sandboxes

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}➜${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Check if Docker Desktop 4.50+ is installed
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker version
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    print_info "Docker version: $DOCKER_VERSION"
    
    # Check if docker sandbox command exists
    if docker sandbox --help &> /dev/null; then
        print_info "Docker Sandboxes is available ✓"
    else
        print_warning "Docker Sandboxes command not found"
        print_warning "Please ensure Docker Desktop 4.50+ is installed"
    fi
}

# Start a basic sandbox
start_basic() {
    print_header "Starting Basic Sandbox"
    print_info "Running: docker sandbox run claude"
    docker sandbox run claude
}

# Start sandbox with environment variables
start_with_env() {
    print_header "Starting Sandbox with Environment Variables"
    docker sandbox run \
        -e NODE_ENV=development \
        -e DEBUG=true \
        -e LOG_LEVEL=info \
        claude
}

# Start sandbox with Docker socket access
start_with_docker() {
    print_header "Starting Sandbox with Docker Socket Access"
    print_warning "This grants the agent access to Docker on your host"
    docker sandbox run --mount-docker-socket claude
}

# Start sandbox with volume mounts
start_with_volumes() {
    print_header "Starting Sandbox with Volume Mounts"
    docker sandbox run \
        -v ~/.cache/pip:/root/.cache/pip \
        -v ~/.npm:/root/.npm \
        claude
}

# Start sandbox with custom template
start_with_template() {
    print_header "Starting Sandbox with Custom Template"
    
    if [ ! -f "Dockerfile.sandbox" ]; then
        print_warning "Dockerfile.sandbox not found, creating default..."
        cat > Dockerfile.sandbox <<'EOF'
# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:claude-code

RUN <<INSTALL
curl -LsSf https://astral.sh/uv/install.sh | sh
. ~/.local/bin/env
uv tool install ruff@latest
INSTALL

ENV PATH="$PATH:~/.local/bin"
EOF
    fi
    
    print_info "Building custom template..."
    docker build -f Dockerfile.sandbox -t my-sandbox-template .
    
    print_info "Starting sandbox with custom template..."
    docker sandbox run --template my-sandbox-template claude
}

# List all sandboxes
list_sandboxes() {
    print_header "Active Sandboxes"
    docker sandbox ls
}

# Show detailed sandbox info
inspect_sandbox() {
    print_header "Sandbox Details"
    
    if [ -z "$1" ]; then
        # Get first sandbox ID if none provided
        SANDBOX_ID=$(docker sandbox ls -q | head -1)
        if [ -z "$SANDBOX_ID" ]; then
            print_error "No sandboxes found"
            exit 1
        fi
    else
        SANDBOX_ID=$1
    fi
    
    print_info "Inspecting sandbox: $SANDBOX_ID"
    docker sandbox inspect "$SANDBOX_ID" | jq '.'
}

# Remove a specific sandbox
remove_sandbox() {
    print_header "Removing Sandbox"
    
    if [ -z "$1" ]; then
        print_error "Usage: $0 remove <sandbox-id>"
        print_info "Use '$0 list' to see available sandboxes"
        exit 1
    fi
    
    print_info "Removing sandbox: $1"
    docker sandbox rm "$1"
    print_info "Sandbox removed successfully"
}

# Remove all sandboxes
cleanup_all() {
    print_header "Cleaning Up All Sandboxes"
    
    SANDBOX_IDS=$(docker sandbox ls -q)
    
    if [ -z "$SANDBOX_IDS" ]; then
        print_info "No sandboxes to remove"
        return
    fi
    
    print_warning "This will remove all Docker sandboxes"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker sandbox rm $(docker sandbox ls -q)
        print_info "All sandboxes removed"
    else
        print_info "Cancelled"
    fi
}

# Show sandbox logs
show_logs() {
    print_header "Sandbox Logs"
    
    if [ -z "$1" ]; then
        SANDBOX_ID=$(docker sandbox ls -q | head -1)
        if [ -z "$SANDBOX_ID" ]; then
            print_error "No sandboxes found"
            exit 1
        fi
    else
        SANDBOX_ID=$1
    fi
    
    print_info "Showing logs for: $SANDBOX_ID"
    docker logs -f "$SANDBOX_ID"
}

# Execute command in sandbox
exec_in_sandbox() {
    print_header "Execute in Sandbox"
    
    if [ -z "$1" ]; then
        SANDBOX_ID=$(docker sandbox ls -q | head -1)
    else
        SANDBOX_ID=$1
    fi
    
    if [ -z "$SANDBOX_ID" ]; then
        print_error "No sandboxes found"
        exit 1
    fi
    
    print_info "Opening shell in: $SANDBOX_ID"
    docker exec -it "$SANDBOX_ID" /bin/bash
}

# Show examples
show_examples() {
    print_header "Docker Sandboxes Examples"
    
    cat <<EOF
${GREEN}Basic Usage:${NC}
  docker sandbox run claude

${GREEN}With Environment Variables:${NC}
  docker sandbox run -e NODE_ENV=development -e DEBUG=true claude

${GREEN}With Volume Mounts:${NC}
  docker sandbox run -v ~/.cache/pip:/root/.cache/pip claude

${GREEN}With Docker Socket (Caution!):${NC}
  docker sandbox run --mount-docker-socket claude

${GREEN}With Custom Template:${NC}
  docker build -f Dockerfile.sandbox -t my-template .
  docker sandbox run --template my-template claude

${GREEN}Management Commands:${NC}
  docker sandbox ls                    # List sandboxes
  docker sandbox inspect <id>          # Inspect sandbox
  docker sandbox rm <id>               # Remove sandbox
  docker sandbox rm \$(docker sandbox ls -q)  # Remove all

${GREEN}Use this script:${NC}
  ./commands.sh start-basic           # Basic sandbox
  ./commands.sh start-with-env        # With env vars
  ./commands.sh start-with-docker     # With Docker access
  ./commands.sh start-with-volumes    # With volume mounts
  ./commands.sh start-custom          # With custom template
  ./commands.sh list                  # List sandboxes
  ./commands.sh inspect [id]          # Inspect sandbox
  ./commands.sh remove <id>           # Remove sandbox
  ./commands.sh cleanup               # Remove all
  ./commands.sh logs [id]             # Show logs
  ./commands.sh exec [id]             # Open shell
  ./commands.sh examples              # Show this help

${YELLOW}For more examples, see EXAMPLES.md${NC}
EOF
}

# Main command router
case "$1" in
    check)
        check_prerequisites
        ;;
    start-basic|start)
        start_basic
        ;;
    start-with-env)
        start_with_env
        ;;
    start-with-docker)
        start_with_docker
        ;;
    start-with-volumes)
        start_with_volumes
        ;;
    start-custom)
        start_with_template
        ;;
    list|ls)
        list_sandboxes
        ;;
    inspect|info)
        inspect_sandbox "$2"
        ;;
    remove|rm)
        remove_sandbox "$2"
        ;;
    cleanup|clean)
        cleanup_all
        ;;
    logs)
        show_logs "$2"
        ;;
    exec|shell)
        exec_in_sandbox "$2"
        ;;
    examples|help|*)
        show_examples
        ;;
esac
