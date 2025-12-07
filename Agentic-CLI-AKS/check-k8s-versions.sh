#!/bin/bash

# Helper script to check available Kubernetes versions

set -e

LOCATION="${1:-eastus}"

echo "Checking available Kubernetes versions in region: $LOCATION"
echo ""

az aks get-versions --location "$LOCATION" --output table

echo ""
echo "To use a specific version, update main.bicepparam:"
echo "  param kubernetesVersion = 'x.xx.x'"
echo ""
