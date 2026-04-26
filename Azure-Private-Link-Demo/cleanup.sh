#!/bin/bash
# =============================================================================
# Tear down the Azure Private Link demo
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()    { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}WARN:${NC} $1"; }
fail()  { echo -e "${RED}ERROR:${NC} $1"; exit 1; }

RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-rg-private-link-demo}"

command -v az >/dev/null || fail "Azure CLI not installed."
az account show >/dev/null 2>&1 || fail "Not logged in. Run 'az login' first."

if ! az group show -n "$RESOURCE_GROUP_NAME" >/dev/null 2>&1; then
    warn "Resource group '$RESOURCE_GROUP_NAME' does not exist. Nothing to do."
    exit 0
fi

warn "About to DELETE resource group: $RESOURCE_GROUP_NAME"
read -rp "Type the resource group name to confirm: " confirm
[[ "$confirm" == "$RESOURCE_GROUP_NAME" ]] || fail "Confirmation did not match. Aborted."

ok "Deleting resource group (running async, will take a few minutes)..."
az group delete -n "$RESOURCE_GROUP_NAME" --yes --no-wait
ok "Delete initiated. Use 'az group show -n $RESOURCE_GROUP_NAME' to track."
