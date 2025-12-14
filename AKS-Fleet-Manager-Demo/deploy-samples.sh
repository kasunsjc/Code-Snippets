#!/bin/bash

# AKS Fleet Manager Demo - Sample Application Deployment
# This script deploys sample applications to demonstrate Fleet Manager capabilities

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Fleet Manager Sample Deployment${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Switch to fleet hub context
echo -e "${YELLOW}Switching to fleet-hub context...${NC}"
kubectl config use-context fleet-hub
echo -e "${GREEN}✓ Context switched to fleet-hub${NC}"
echo ""

# Deploy namespace
echo -e "${YELLOW}Deploying demo namespace...${NC}"
kubectl apply -f kubernetes-manifests/01-namespace.yaml
echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

# Deploy nginx application
echo -e "${YELLOW}Deploying nginx demo application...${NC}"
kubectl apply -f kubernetes-manifests/02-nginx-deployment.yaml
echo -e "${GREEN}✓ Nginx application deployed${NC}"
echo ""

# Deploy ClusterResourcePlacement
echo -e "${YELLOW}Creating ClusterResourcePlacement to propagate resources...${NC}"
kubectl apply -f kubernetes-manifests/00-cluster-resource-placement.yaml
echo -e "${GREEN}✓ ClusterResourcePlacement created${NC}"
echo ""

# Wait for placement to be applied
echo -e "${YELLOW}Waiting for resources to propagate to member clusters...${NC}"
sleep 10

# Check placement status
echo -e "${YELLOW}Checking ClusterResourcePlacement status...${NC}"
kubectl get clusterresourceplacement demo-app-placement -o wide
echo ""

# Deploy PickN placement example
echo -e "${YELLOW}Deploying PickN placement example...${NC}"
kubectl apply -f kubernetes-manifests/03-pickn-placement.yaml
echo -e "${GREEN}✓ PickN placement created${NC}"
echo ""

# Deploy multi-cluster service
echo -e "${YELLOW}Deploying multi-cluster service example...${NC}"
kubectl apply -f kubernetes-manifests/05-multi-cluster-service.yaml
echo -e "${GREEN}✓ Multi-cluster service deployed${NC}"
echo ""

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Sample Deployment Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${BLUE}To verify the deployment:${NC}"
echo ""
echo "1. Check ClusterResourcePlacements:"
echo "   kubectl get clusterresourceplacement"
echo ""
echo "2. Check placement status:"
echo "   kubectl describe clusterresourceplacement demo-app-placement"
echo ""
echo "3. View member clusters:"
echo "   kubectl get memberclusters"
echo ""
echo "4. Check resources in member clusters:"
echo "   kubectl get pods -n fleet-demo --context <member-cluster-context>"
echo ""
echo "5. Monitor fleet resources:"
echo "   kubectl get all -n fleet-demo"
echo ""
