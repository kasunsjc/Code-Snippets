#!/bin/bash

# Install Cilium CLI on macOS/Linux
# Use this script if you don't already have the Cilium CLI

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_info() {
    echo -e "${BLUE}INFO:${NC} $1"
}

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
esac

echo ""
echo "=========================================="
echo "   Cilium CLI & Hubble CLI Installer"
echo "=========================================="
echo ""
print_info "Detected OS: $OS, Arch: $ARCH"

# Install Cilium CLI
if command -v cilium &> /dev/null; then
    print_message "Cilium CLI is already installed: $(cilium version --client)"
else
    print_message "Installing Cilium CLI..."
    if [[ "$OS" == "darwin" ]]; then
        brew install cilium-cli
    else
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-${OS}-${ARCH}.tar.gz{,.sha256sum}"
        sha256sum --check "cilium-${OS}-${ARCH}.tar.gz.sha256sum"
        sudo tar xzvfC "cilium-${OS}-${ARCH}.tar.gz" /usr/local/bin
        rm "cilium-${OS}-${ARCH}.tar.gz" "cilium-${OS}-${ARCH}.tar.gz.sha256sum"
    fi
    print_message "Cilium CLI installed successfully!"
fi

# Install Hubble CLI
if command -v hubble &> /dev/null; then
    print_message "Hubble CLI is already installed: $(hubble version)"
else
    print_message "Installing Hubble CLI..."
    if [[ "$OS" == "darwin" ]]; then
        brew install hubble
    else
        HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
        curl -L --fail --remote-name-all "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-${OS}-${ARCH}.tar.gz{,.sha256sum}"
        sha256sum --check "hubble-${OS}-${ARCH}.tar.gz.sha256sum"
        sudo tar xzvfC "hubble-${OS}-${ARCH}.tar.gz" /usr/local/bin
        rm "hubble-${OS}-${ARCH}.tar.gz" "hubble-${OS}-${ARCH}.tar.gz.sha256sum"
    fi
    print_message "Hubble CLI installed successfully!"
fi

echo ""
print_message "All tools installed!"
echo ""
cilium version --client 2>/dev/null || true
hubble version 2>/dev/null || true
