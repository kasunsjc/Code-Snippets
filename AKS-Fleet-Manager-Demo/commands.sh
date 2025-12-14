# AKS Fleet Manager - Useful Commands

## Fleet Management Commands

### View Fleet Information
```bash
# Get fleet details
az fleet show \
  --resource-group rg-aks-fleet-demo \
  --name <fleet-name>

# List all fleets in subscription
az fleet list --output table

# Get fleet credentials
az fleet get-credentials \
  --resource-group rg-aks-fleet-demo \
  --name <fleet-name>
```

### Fleet Member Management
```bash
# List fleet members
az fleet member list \
  --resource-group rg-aks-fleet-demo \
  --fleet-name <fleet-name> \
  --output table

# Get member details
az fleet member show \
  --resource-group rg-aks-fleet-demo \
  --fleet-name <fleet-name> \
  --name <member-name>

# Remove a member
az fleet member delete \
  --resource-group rg-aks-fleet-demo \
  --fleet-name <fleet-name> \
  --name <member-name>
```

## Kubernetes Fleet Commands

### Cluster Resource Placement
```bash
# List all ClusterResourcePlacements
kubectl get clusterresourceplacement

# Describe placement status
kubectl describe clusterresourceplacement <placement-name>

# Get placement with detailed status
kubectl get clusterresourceplacement <placement-name> -o yaml

# Watch placement status
kubectl get clusterresourceplacement -w
```

### Member Cluster Management
```bash
# List member clusters
kubectl get memberclusters

# Get member cluster details
kubectl describe membercluster <cluster-name>

# Check member cluster health
kubectl get membercluster <cluster-name> -o jsonpath='{.status.conditions[*].type}'
```

### Multi-Cluster Service Discovery
```bash
# List ServiceExports
kubectl get serviceexport -n <namespace>

# List ServiceImports
kubectl get serviceimport -n <namespace>

# Describe multi-cluster service
kubectl describe serviceexport <service-name> -n <namespace>
```

### Resource Override
```bash
# List ClusterResourceOverrides
kubectl get clusterresourceoverride

# Apply override
kubectl apply -f kubernetes-manifests/04-resource-override.yaml

# Check override status
kubectl describe clusterresourceoverride <override-name>
```

## Monitoring and Troubleshooting

### Check Resource Propagation
```bash
# Check if resources are propagated to specific cluster
kubectl get pods -n fleet-demo --context <member-cluster-context>

# Compare resources across clusters
for ctx in $(kubectl config get-contexts -o name | grep aks-member); do
  echo "=== Context: $ctx ==="
  kubectl get pods -n fleet-demo --context $ctx
done
```

### View Fleet Hub Logs
```bash
# Get fleet-system pods
kubectl get pods -n fleet-system

# View fleet controller logs
kubectl logs -n fleet-system deployment/fleet-controller-manager -f

# View placement controller logs
kubectl logs -n fleet-system deployment/fleet-controller-manager -c placement-controller -f
```

### Check Placement Conditions
```bash
# Get detailed placement status
kubectl get clusterresourceplacement <placement-name> \
  -o jsonpath='{.status.conditions[*]}' | jq

# Check placement decisions
kubectl get clusterresourceplacement <placement-name> \
  -o jsonpath='{.status.placementStatuses[*]}'
```

## Update Management

### Fleet Update Run
```bash
# Create update run (Azure CLI)
az fleet updaterun create \
  --resource-group rg-aks-fleet-demo \
  --fleet-name <fleet-name> \
  --name <update-run-name> \
  --upgrade-type Full \
  --kubernetes-version 1.29.0

# List update runs
az fleet updaterun list \
  --resource-group rg-aks-fleet-demo \
  --fleet-name <fleet-name> \
  --output table

# Get update run status
az fleet updaterun show \
  --resource-group rg-aks-fleet-demo \
  --fleet-name <fleet-name> \
  --name <update-run-name>

# Stop update run
az fleet updaterun stop \
  --resource-group rg-aks-fleet-demo \
  --fleet-name <fleet-name> \
  --name <update-run-name>
```

## Switch Between Contexts
```bash
# List all contexts
kubectl config get-contexts

# Switch to fleet hub
kubectl config use-context fleet-hub

# Switch to member cluster 1
kubectl config use-context aks-member1-demo

# Switch to member cluster 2
kubectl config use-context aks-member2-demo

# Execute command on specific context
kubectl get pods --context fleet-hub
```

## Verification Commands

### Verify Fleet Setup
```bash
# Check fleet hub cluster
kubectl cluster-info --context fleet-hub

# Verify member clusters are joined
kubectl get memberclusters

# Check fleet-system namespace
kubectl get all -n fleet-system
```

### Test Resource Propagation
```bash
# Deploy test namespace to hub
kubectl create namespace test-propagation --context fleet-hub

# Create placement for test namespace
cat <<EOF | kubectl apply -f -
apiVersion: placement.kubernetes-fleet.io/v1beta1
kind: ClusterResourcePlacement
metadata:
  name: test-placement
spec:
  resourceSelectors:
    - group: ""
      kind: Namespace
      name: test-propagation
      version: v1
  policy:
    placementType: PickAll
EOF

# Verify namespace propagated to members
kubectl get namespace test-propagation --context aks-member1-demo
kubectl get namespace test-propagation --context aks-member2-demo
```

## Performance and Diagnostics

### Get Fleet Metrics
```bash
# Query Log Analytics for fleet metrics
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "KubePodInventory | where Namespace == 'fleet-system' | summarize count() by Computer" \
  --output table
```

### Export Fleet Configuration
```bash
# Export all fleet resources
kubectl get clusterresourceplacement -o yaml > fleet-placements.yaml
kubectl get membercluster -o yaml > fleet-members.yaml
```
