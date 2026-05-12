#!/bin/bash
# =============================================================================
# VCluster Demo - Install Required CLI Tools
# =============================================================================
# Installs vcluster CLI, kubectl, helm and other tools needed for all demos.
# Supports macOS (Homebrew) and Linux.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

VCLUSTER_VERSION="${VCLUSTER_VERSION:-v0.20.0}"
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Normalise architecture name
# Different systems report architecture differently (x86_64 vs amd64, aarch64 vs arm64)
# This standardizes them to match download URLs (amd64 and arm64)
[[ "$ARCH" == "x86_64" ]]  && ARCH="amd64"
[[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
[[ "$ARCH" == "arm64" ]]   && ARCH="arm64"

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}  VCluster Demo — Tool Installer      ${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "  OS   : $OS"
echo "  Arch : $ARCH"
echo ""

# --------------------------------------------------
# vcluster CLI
# --------------------------------------------------
install_vcluster() {
  # PURPOSE: Install vcluster CLI (command-line tool for managing virtual clusters)
  # vcluster is required to create, connect, and delete virtual Kubernetes clusters
  
  # First check if vcluster is already installed to avoid reinstalling
  # command -v: returns path if executable is found in $PATH
  # &> /dev/null: suppress both stdout and stderr (redirects to /dev/null)
  if command -v vcluster &> /dev/null; then
    echo -e "${GREEN}  ✓ vcluster already installed: $(vcluster version 2>/dev/null | head -1)${NC}"
    return
  fi

  echo -e "${YELLOW}Installing vcluster CLI $VCLUSTER_VERSION...${NC}"

  # Install via appropriate method based on OS
  # macOS with Homebrew: use brew install (simplest, managed updates)
  # Linux or macOS without Homebrew: download binary from GitHub releases
  if [[ "$OS" == "darwin" ]] && command -v brew &> /dev/null; then
    # Homebrew tap: loft-sh/tap provides vcluster formula
    # Homebrew automatically puts binary in /usr/local/bin/vcluster
    brew install loft-sh/tap/vcluster
  else
    # Manual installation from GitHub releases
    # Construct download URL: https://github.com/loft-sh/vcluster/releases/download/v0.20.0/vcluster-linux-amd64
    local url="https://github.com/loft-sh/vcluster/releases/download/${VCLUSTER_VERSION}/vcluster-${OS}-${ARCH}"
    # curl -sL: silent mode, follow redirects
    # -o /tmp/vcluster: save to temporary location
    curl -sL "$url" -o /tmp/vcluster
    # chmod +x: make binary executable (rwxr-xr-x permissions)
    chmod +x /tmp/vcluster
    # sudo mv: move to system PATH as root (requires sudo password input)
    sudo mv /tmp/vcluster /usr/local/bin/vcluster
  fi

  echo -e "${GREEN}  ✓ vcluster installed: $(vcluster version 2>/dev/null | head -1)${NC}"
}

# --------------------------------------------------
# kubectl
# --------------------------------------------------
install_kubectl() {
  # PURPOSE: Install kubectl (Kubernetes command-line tool)
  # kubectl is required to interact with Kubernetes clusters, create resources, debug pods, etc.
  
  if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}  ✓ kubectl already installed${NC}"
    return
  fi

  echo -e "${YELLOW}Installing kubectl...${NC}"
  
  if [[ "$OS" == "darwin" ]] && command -v brew &> /dev/null; then
    # Homebrew: simplest and keeps kubectl updated
    brew install kubectl
  else
    # Manual download from Kubernetes official repository
    # Fetch stable Kubernetes version (e.g., v1.31.0)
    # curl -sL: silent mode, follow redirects
    local k8s_version
    k8s_version=$(curl -sL https://dl.k8s.io/release/stable.txt)
    
    # Download kubectl binary for specific OS and architecture
    # https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl
    curl -sLO "https://dl.k8s.io/release/${k8s_version}/bin/${OS}/${ARCH}/kubectl"
    # Make executable and move to system PATH
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
  fi
  
  echo -e "${GREEN}  ✓ kubectl installed${NC}"
}

# --------------------------------------------------
# Helm
# --------------------------------------------------
install_helm() {
  # PURPOSE: Install Helm (package manager for Kubernetes)
  # Helm is required to install NGINX Ingress Controller and other Kubernetes packages
  
  if command -v helm &> /dev/null; then
    echo -e "${GREEN}  ✓ Helm already installed: $(helm version --short)${NC}"
    return
  fi

  echo -e "${YELLOW}Installing Helm...${NC}"
  
  if [[ "$OS" == "darwin" ]] && command -v brew &> /dev/null; then
    # Homebrew: managed installation with auto-updates
    brew install helm
  else
    # Official Helm installation script
    # get-helm-3 script: downloads latest Helm 3 binary and installs to /usr/local/bin
    # curl -fsSL: fail on HTTP errors, silent mode, show errors, follow redirects
    # | bash: pipe output to bash for execution
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  
  echo -e "${GREEN}  ✓ Helm installed${NC}"
}

# --------------------------------------------------
# Azure CLI
# --------------------------------------------------
check_azure_cli() {
  if command -v az &> /dev/null; then
    echo -e "${GREEN}  ✓ Azure CLI already installed: $(az version --query '"azure-cli"' -o tsv)${NC}"
  else
    echo -e "${YELLOW}  Azure CLI not found.${NC}"
    echo "  Install manually: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  fi
}

# --------------------------------------------------
# Main
# --------------------------------------------------
echo -e "${YELLOW}Installing / verifying tools...${NC}"
echo ""

install_vcluster
install_kubectl
install_helm
check_azure_cli

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${GREEN}  All tools ready!${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo -e "  Versions:"
command -v vcluster &> /dev/null  && echo "    vcluster : $(vcluster version 2>/dev/null | head -1 || echo 'installed')"
command -v kubectl  &> /dev/null  && echo "    kubectl  : $(kubectl version --client --short 2>/dev/null | head -1)"
command -v helm     &> /dev/null  && echo "    helm     : $(helm version --short)"
command -v az       &> /dev/null  && echo "    azure-cli: $(az version --query '"azure-cli"' -o tsv)"
echo ""
echo -e "${YELLOW}  Next step:${NC} Run ./deploy.sh to create the host AKS cluster."
echo ""
