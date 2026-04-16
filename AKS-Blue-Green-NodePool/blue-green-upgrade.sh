#!/bin/bash
set -euo pipefail

# ============================================================
# AKS Blue-Green Node Pool Upgrade Demo
# ============================================================
# This script demonstrates the blue-green node pool upgrade
# strategy for AKS. It walks through:
#   1. Creating a new "green" node pool
#   2. Migrating workloads from "blue" to "green"
#   3. Cordoning and draining the "blue" node pool
#   4. Removing the old "blue" node pool
#
# Reference:
# https://learn.microsoft.com/en-us/azure/aks/blue-green-node-pool-upgrade
# ============================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="aks-bluegreen-demo"
CLUSTER_NAME="aks-bluegreen-cluster"

# Functions
print_message() {
    echo -e "${GREEN}==>${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  STEP $1: $2${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

wait_for_user() {
    echo ""
    read -p "Press Enter to continue to the next step..."
    echo ""
}

# ============================================================
# Step 0: Verify Current State
# ============================================================
step_verify_current_state() {
    print_step "0" "Verify Current State"

    print_message "Current node pools:"
    az aks nodepool list \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table

    echo ""
    print_message "Nodes and their labels:"
    kubectl get nodes -L environment

    echo ""
    print_message "Current pods running on blue nodes:"
    kubectl get pods -n demo -o wide

    echo ""
    print_message "Current state: Workloads are running on the BLUE node pool."
}

# ============================================================
# Step 1: Create Green Node Pool
# ============================================================
step_create_green_pool() {
    print_step "1" "Create Green Node Pool"

    print_message "Adding a new 'green' node pool to the cluster..."
    print_warning "This may take 3-5 minutes..."

    az aks nodepool add \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name green \
        --node-count 3 \
        --node-vm-size Standard_D2s_v4 \
        --os-sku AzureLinux \
        --labels environment=green \
        --mode User \
        --output table

    print_message "Green node pool created successfully!"

    echo ""
    print_message "Updated node pools:"
    az aks nodepool list \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table

    echo ""
    print_message "All nodes with environment labels:"
    kubectl get nodes -L environment
}

# ============================================================
# Step 2: Migrate Workloads to Green
# ============================================================
step_migrate_workloads() {
    print_step "2" "Migrate Workloads from Blue to Green"

    print_message "Updating sample-app nodeSelector from 'blue' to 'green'..."

    kubectl patch deployment sample-app -n demo --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/nodeSelector/environment", "value": "green"}]'

    print_message "Waiting for rollout to complete..."
    kubectl rollout status deployment/sample-app -n demo --timeout=120s

    echo ""
    print_message "Pods are now running on green nodes:"
    kubectl get pods -n demo -o wide

    echo ""
    print_message "Workloads successfully migrated to the GREEN node pool!"
}

# ============================================================
# Step 3: Cordon and Drain Blue Nodes
# ============================================================
step_cordon_drain_blue() {
    print_step "3" "Cordon and Drain Blue Node Pool"

    print_message "Cordoning blue nodes (preventing new pod scheduling)..."

    BLUE_NODES=$(kubectl get nodes -l environment=blue -o jsonpath='{.items[*].metadata.name}')

    if [ -z "$BLUE_NODES" ]; then
        print_warning "No blue nodes found. Skipping cordon/drain."
        return
    fi

    for node in $BLUE_NODES; do
        print_message "  Cordoning node: $node"
        kubectl cordon "$node"
    done

    echo ""
    print_message "Draining blue nodes (evicting remaining pods)..."

    for node in $BLUE_NODES; do
        print_message "  Draining node: $node"
        kubectl drain "$node" \
            --ignore-daemonsets \
            --delete-emptydir-data \
            --force \
            --timeout=120s 2>&1 | grep -E "evict|drain|cordon" || true
    done

    echo ""
    print_message "Blue nodes cordoned and drained!"

    echo ""
    print_message "Node status (blue nodes should show SchedulingDisabled):"
    kubectl get nodes -L environment
}

# ============================================================
# Step 4: Remove Blue Node Pool
# ============================================================
step_remove_blue_pool() {
    print_step "4" "Remove Blue Node Pool"

    print_warning "This will permanently delete the blue node pool."
    read -p "Continue? (yes/no): " confirmation

    if [ "$confirmation" != "yes" ]; then
        print_message "Skipping blue node pool removal."
        return
    fi

    print_message "Deleting the blue node pool..."
    print_warning "This may take 2-3 minutes..."

    az aks nodepool delete \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name blue \
        --no-wait

    print_message "Blue node pool deletion initiated!"
}

# ============================================================
# Step 5: Verify Final State
# ============================================================
step_verify_final_state() {
    print_step "5" "Verify Final State"

    print_message "Final node pools:"
    az aks nodepool list \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table

    echo ""
    print_message "Final nodes:"
    kubectl get nodes -L environment

    echo ""
    print_message "Pods running on green nodes:"
    kubectl get pods -n demo -o wide

    echo ""
    echo "=========================================="
    echo "   Blue-Green Upgrade Complete!"
    echo "=========================================="
    echo ""
    echo "  ✅ Green node pool is now active"
    echo "  ✅ Workloads migrated successfully"
    echo "  ✅ Blue node pool removed"
    echo ""
    echo "  The 'green' pool is now your production"
    echo "  node pool. For the next upgrade cycle,"
    echo "  create a new 'blue' pool and repeat."
    echo ""
    echo "=========================================="
    echo ""
}

# ============================================================
# Main Execution
# ============================================================
main() {
    print_message "Starting AKS Blue-Green Node Pool Upgrade Demo"
    print_message "================================================"
    echo ""
    print_message "This demo walks through a blue-green node pool"
    print_message "upgrade strategy step by step."
    echo ""

    step_verify_current_state
    wait_for_user

    step_create_green_pool
    wait_for_user

    step_migrate_workloads
    wait_for_user

    step_cordon_drain_blue
    wait_for_user

    step_remove_blue_pool
    wait_for_user

    step_verify_final_state

    print_message "Blue-Green Node Pool Upgrade Demo completed!"
}

main
