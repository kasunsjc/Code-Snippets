#!/bin/bash
set -euo pipefail

# ============================================================
# AKS Blue-Green Node Pool Upgrade Demo (Preview Feature)
# ============================================================
# This script demonstrates the AKS blue-green node pool upgrade
# preview feature. Unlike manual blue-green deployments, this
# uses the built-in AKS upgrade strategy that automatically:
#   - Cordons the existing (blue) nodes
#   - Creates a parallel (green) node pool
#   - Drains workloads in configurable batches
#   - Provides a soak period for validation
#   - Supports rollback during the final soak period
#
# Prerequisites:
#   - aks-preview CLI extension installed
#   - Cluster deployed with deploy.sh
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
NODEPOOL_NAME="userpool"

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
# Step 0: Verify Prerequisites and Current State
# ============================================================
step_verify_current_state() {
    print_step "0" "Verify Prerequisites and Current State"

    print_message "Checking aks-preview extension..."
    if ! az extension show --name aks-preview &> /dev/null; then
        print_error "aks-preview extension is not installed. Run deploy.sh first."
        exit 1
    fi

    AKS_PREVIEW_VERSION=$(az extension show --name aks-preview --query version -o tsv)
    print_message "aks-preview version: $AKS_PREVIEW_VERSION"

    echo ""
    print_message "Current node pools:"
    az aks nodepool list \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table

    echo ""
    print_message "Current node pool upgrade settings:"
    az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query "{name:name, kubernetesVersion:currentOrchestratorVersion, upgradeSettings:upgradeSettings}" \
        --output json

    echo ""
    print_message "Current Kubernetes version:"
    CURRENT_VERSION=$(az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query currentOrchestratorVersion \
        --output tsv)
    print_message "  Node pool '$NODEPOOL_NAME' is running Kubernetes $CURRENT_VERSION"

    echo ""
    print_message "Available upgrade versions:"
    az aks get-upgrades \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table 2>/dev/null || print_warning "Could not retrieve upgrade versions."

    echo ""
    print_message "Current pods:"
    kubectl get pods -n demo -o wide 2>/dev/null || print_warning "No demo namespace found."

    echo ""
    print_message "Current nodes:"
    kubectl get nodes -o wide
}

# ============================================================
# Step 1: Review Blue-Green Settings
# ============================================================
step_review_settings() {
    print_step "1" "Review Blue-Green Upgrade Settings"

    print_message "The node pool '$NODEPOOL_NAME' is configured with blue-green strategy."
    echo ""
    echo "  The blue-green upgrade process will:"
    echo ""
    echo "  1. Cordon existing (blue) nodes — mark as unschedulable"
    echo "  2. Create a new (green) node pool — with the target version"
    echo "  3. Drain workloads in batches — respecting PodDisruptionBudgets"
    echo "  4. Pause between batches — for observation (batch soak)"
    echo "  5. Final soak period — for validation before committing"
    echo "  6. Delete blue nodes — after soak period expires"
    echo ""

    print_message "Current blue-green upgrade settings:"
    az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query "upgradeSettings" \
        --output json

    echo ""
    print_message "You can customize these settings before upgrading:"
    echo ""
    echo "  az aks nodepool update \\"
    echo "      --cluster-name $CLUSTER_NAME \\"
    echo "      --resource-group $RESOURCE_GROUP \\"
    echo "      --name $NODEPOOL_NAME \\"
    echo "      --drain-batch-size '50%' \\"
    echo "      --drain-timeout-bg 30 \\"
    echo "      --batch-soak-duration 5 \\"
    echo "      --final-soak-duration 60"
}

# ============================================================
# Step 2: Upgrade Control Plane (if needed)
# ============================================================
step_upgrade_control_plane() {
    print_step "2" "Upgrade Control Plane (if needed)"

    print_message "Checking current control plane and node pool versions..."

    CONTROL_PLANE_VERSION=$(az aks show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query kubernetesVersion \
        --output tsv)

    NODEPOOL_VERSION=$(az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query currentOrchestratorVersion \
        --output tsv)

    # Get available upgrade target for the control plane
    TARGET_VERSION=$(az aks get-upgrades \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "controlPlaneProfile.upgrades[0].kubernetesVersion" \
        --output tsv 2>/dev/null || echo "")

    print_message "Control plane version: $CONTROL_PLANE_VERSION"
    print_message "Node pool version:     $NODEPOOL_VERSION"
    print_message "Available target:      ${TARGET_VERSION:-None}"

    if [ -z "$TARGET_VERSION" ] || [ "$TARGET_VERSION" = "None" ]; then
        print_warning "No Kubernetes version upgrade available for the control plane."
        print_message "You can still perform a node image upgrade in the next step."
        return
    fi

    echo ""
    print_warning "AKS requires the control plane version >= node pool version."
    print_warning "The control plane must be upgraded BEFORE the node pool."
    print_message "Upgrading control plane from $CONTROL_PLANE_VERSION to $TARGET_VERSION..."
    echo ""
    read -p "Continue with control plane upgrade? (yes/no): " confirmation

    if [ "$confirmation" != "yes" ]; then
        print_message "Control plane upgrade skipped."
        return
    fi

    print_warning "This may take 5-10 minutes..."

    az aks upgrade \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --kubernetes-version "$TARGET_VERSION" \
        --control-plane-only \
        --yes

    print_message "Control plane upgraded to $TARGET_VERSION!"

    echo ""
    print_message "Verifying control plane version:"
    az aks show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "{name:name, kubernetesVersion:kubernetesVersion}" \
        --output json
}

# ============================================================
# Step 3: Start Blue-Green Node Pool Upgrade
# ============================================================
step_start_upgrade() {
    print_step "3" "Start Blue-Green Node Pool Upgrade"

    # Determine target version
    print_message "Determining upgrade target..."

    CONTROL_PLANE_VERSION=$(az aks show \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query kubernetesVersion \
        --output tsv)

    NODEPOOL_VERSION=$(az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query currentOrchestratorVersion \
        --output tsv)

    print_message "Control plane version: $CONTROL_PLANE_VERSION"
    print_message "Node pool version:     $NODEPOOL_VERSION"

    # Check if control plane is ahead of the node pool (K8s version upgrade possible)
    if [ "$CONTROL_PLANE_VERSION" != "$NODEPOOL_VERSION" ]; then
        echo ""
        print_message "Control plane ($CONTROL_PLANE_VERSION) is ahead of node pool ($NODEPOOL_VERSION)."
        print_message "Starting blue-green Kubernetes version upgrade for '$NODEPOOL_NAME'..."
        print_warning "A parallel green node pool will be created (doubles capacity temporarily)."
        echo ""
        read -p "Continue? (yes/no): " confirmation

        if [ "$confirmation" != "yes" ]; then
            print_message "Upgrade skipped."
            return
        fi

        print_message "Starting blue-green upgrade to Kubernetes $CONTROL_PLANE_VERSION..."

        az aks nodepool upgrade \
            --cluster-name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$NODEPOOL_NAME" \
            --kubernetes-version "$CONTROL_PLANE_VERSION" \
            --no-wait

        print_message "Blue-green Kubernetes version upgrade initiated!"
    else
        print_message "Node pool is already at the control plane version ($CONTROL_PLANE_VERSION)."
        print_message "Performing a node image upgrade instead..."
        echo ""
        print_message "Starting blue-green node image upgrade for '$NODEPOOL_NAME'..."
        print_warning "This will create a green pool, drain blue pool in batches, and soak."
        echo ""
        read -p "Continue? (yes/no): " confirmation

        if [ "$confirmation" != "yes" ]; then
            print_message "Upgrade skipped."
            return
        fi

        az aks nodepool upgrade \
            --cluster-name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name "$NODEPOOL_NAME" \
            --node-image-only \
            --no-wait

        print_message "Blue-green node image upgrade initiated!"
    fi

    echo ""
    print_message "The upgrade is running in the background. Monitor with:"
    echo "  az aks nodepool show -g $RESOURCE_GROUP --cluster-name $CLUSTER_NAME -n $NODEPOOL_NAME --query provisioningState -o tsv"
    echo "  kubectl get nodes -o wide"
}

# ============================================================
# Step 4: Monitor Upgrade Progress
# ============================================================
step_monitor_upgrade() {
    print_step "4" "Monitor Upgrade Progress"

    print_message "Checking node pool provisioning state..."

    PROVISIONING_STATE=$(az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query provisioningState \
        --output tsv)

    print_message "Provisioning state: $PROVISIONING_STATE"

    echo ""
    print_message "Node pools:"
    az aks nodepool list \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table

    echo ""
    print_message "Nodes (look for both blue and green nodes):"
    kubectl get nodes -o wide

    echo ""
    print_message "Pod status:"
    kubectl get pods -n demo -o wide 2>/dev/null || print_warning "No demo namespace found."

    echo ""
    print_message "During the upgrade you can:"
    echo ""
    echo "  Monitor continuously:"
    echo "    watch -n 10 kubectl get nodes -o wide"
    echo ""
    echo "  Check pod migrations:"
    echo "    watch -n 10 kubectl get pods -n demo -o wide"
    echo ""
    echo "  Pause/abort the upgrade:"
    echo "    az aks nodepool operation-abort -g $RESOURCE_GROUP --cluster-name $CLUSTER_NAME -n $NODEPOOL_NAME"
}

# ============================================================
# Step 5: Demonstrate Abort and Rollback
# ============================================================
step_demonstrate_rollback() {
    print_step "5" "Abort and Rollback (Optional)"

    print_message "If you need to abort the upgrade and rollback:"
    echo ""
    echo "  Step 1 — Abort the ongoing upgrade:"
    echo "    az aks nodepool operation-abort \\"
    echo "        --name $NODEPOOL_NAME \\"
    echo "        --cluster-name $CLUSTER_NAME \\"
    echo "        --resource-group $RESOURCE_GROUP"
    echo ""
    echo "  Step 2 — Rollback to the original blue pool:"
    echo "    az aks nodepool rollback \\"
    echo "        --name $NODEPOOL_NAME \\"
    echo "        --cluster-name $CLUSTER_NAME \\"
    echo "        --resource-group $RESOURCE_GROUP"
    echo ""
    echo "  ⚠️  Rollback is only available during the final soak period."
    echo "  Once the soak period expires and the blue pool is deleted,"
    echo "  rollback is no longer possible."
    echo ""

    read -p "Do you want to abort the current upgrade? (yes/no): " confirmation

    if [ "$confirmation" = "yes" ]; then
        print_message "Aborting upgrade..."
        az aks nodepool operation-abort \
            --name "$NODEPOOL_NAME" \
            --cluster-name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" 2>&1 || print_warning "No active upgrade to abort."

        echo ""
        read -p "Do you also want to rollback? (yes/no): " rollback_confirmation

        if [ "$rollback_confirmation" = "yes" ]; then
            print_message "Rolling back..."
            az aks nodepool rollback \
                --name "$NODEPOOL_NAME" \
                --cluster-name "$CLUSTER_NAME" \
                --resource-group "$RESOURCE_GROUP" 2>&1 || print_warning "Rollback not available at this stage."
        fi
    else
        print_message "Skipping abort/rollback."
    fi
}

# ============================================================
# Step 6: Verify Final State
# ============================================================
step_verify_final_state() {
    print_step "6" "Verify Final State"

    print_message "Final node pool state:"
    az aks nodepool show \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NODEPOOL_NAME" \
        --query "{name:name, provisioningState:provisioningState, kubernetesVersion:currentOrchestratorVersion, count:count}" \
        --output json

    echo ""
    print_message "Node pools:"
    az aks nodepool list \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output table

    echo ""
    print_message "Nodes:"
    kubectl get nodes -o wide

    echo ""
    print_message "Pod status:"
    kubectl get pods -n demo -o wide 2>/dev/null || true

    echo ""
    echo "=========================================="
    echo "   Blue-Green Upgrade Demo Complete!"
    echo "=========================================="
    echo ""
    echo "  The AKS blue-green node pool upgrade"
    echo "  preview feature automates the entire"
    echo "  blue-green lifecycle:"
    echo ""
    echo "  1. Upgrade control plane to target version"
    echo "  2. Cordon blue → Create green"
    echo "  3. Drain in batches → Soak between batches"
    echo "  4. Final soak → Commit or rollback"
    echo ""
    echo "  No manual nodeSelector patching, cordoning,"
    echo "  or draining required!"
    echo ""
    echo "=========================================="
    echo ""
}

# ============================================================
# Main Execution
# ============================================================
main() {
    print_message "AKS Blue-Green Node Pool Upgrade Demo (Preview)"
    print_message "================================================"
    echo ""
    print_message "This demo demonstrates the AKS preview feature"
    print_message "for automated blue-green node pool upgrades."
    echo ""

    step_verify_current_state
    wait_for_user

    step_review_settings
    wait_for_user

    step_upgrade_control_plane
    wait_for_user

    step_start_upgrade
    wait_for_user

    step_monitor_upgrade
    wait_for_user

    step_demonstrate_rollback
    wait_for_user

    step_verify_final_state

    print_message "Blue-Green Node Pool Upgrade Demo completed!"
}

main
