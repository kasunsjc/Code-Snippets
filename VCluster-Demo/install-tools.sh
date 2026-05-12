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
  if command -v vcluster &> /dev/null; then
    echo -e "${GREEN}  ✓ vcluster already installed: $(vcluster version 2>/dev/null | head -1)${NC}"
    return
  fi

  echo -e "${YELLOW}Installing vcluster CLI $VCLUSTER_VERSION...${NC}"

  if [[ "$OS" == "darwin" ]] && command -v brew &> /dev/null; then
    brew install loft-sh/tap/vcluster
  else
    local url="https://github.com/loft-sh/vcluster/releases/download/${VCLUSTER_VERSION}/vcluster-${OS}-${ARCH}"
    curl -sL "$url" -o /tmp/vcluster
    chmod +x /tmp/vcluster
    sudo mv /tmp/vcluster /usr/local/bin/vcluster
  fi

  echo -e "${GREEN}  ✓ vcluster installed: $(vcluster version 2>/dev/null | head -1)${NC}"
}

# --------------------------------------------------
# kubectl
# --------------------------------------------------
install_kubectl() {
  if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}  ✓ kubectl already installed${NC}"
    return
  fi

  echo -e "${YELLOW}Installing kubectl...${NC}"
  if [[ "$OS" == "darwin" ]] && command -v brew &> /dev/null; then
    brew install kubectl
  else
    local k8s_version
    k8s_version=$(curl -sL https://dl.k8s.io/release/stable.txt)
    curl -sLO "https://dl.k8s.io/release/${k8s_version}/bin/${OS}/${ARCH}/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
  fi
  echo -e "${GREEN}  ✓ kubectl installed${NC}"
}

# --------------------------------------------------
# Helm
# --------------------------------------------------
install_helm() {
  if command -v helm &> /dev/null; then
    echo -e "${GREEN}  ✓ Helm already installed: $(helm version --short)${NC}"
    return
  fi

  echo -e "${YELLOW}Installing Helm...${NC}"
  if [[ "$OS" == "darwin" ]] && command -v brew &> /dev/null; then
    brew install helm
  else
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
