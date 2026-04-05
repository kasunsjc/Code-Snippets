#!/bin/bash

# Test script to verify Cilium network policies are working
# Run this after deploying sample apps and policies

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_pass() {
    echo -e "  ${GREEN}✓ PASS:${NC} $1"
}

print_fail() {
    echo -e "  ${RED}✗ FAIL:${NC} $1"
}

print_test() {
    echo -e "${BLUE}TEST:${NC} $1"
}

print_section() {
    echo ""
    echo -e "${YELLOW}--- $1 ---${NC}"
}

FRONTEND_POD=$(kubectl -n cilium-demo get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
BACKEND_POD=$(kubectl -n cilium-demo get pod -l app=backend-api -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "=========================================="
echo "   Cilium Network Policy Tests"
echo "=========================================="
echo ""
echo "Using pods:"
echo "  Frontend: $FRONTEND_POD"
echo "  Backend:  $BACKEND_POD"

print_section "Test 1: Frontend -> Backend (should SUCCEED)"
print_test "Frontend can reach backend-api on port 80..."
if kubectl -n cilium-demo exec "$FRONTEND_POD" -- wget -qO- --timeout=5 http://backend-api 2>/dev/null | head -1 > /dev/null 2>&1; then
    print_pass "Frontend -> Backend: Connection allowed"
else
    print_fail "Frontend -> Backend: Connection blocked (unexpected)"
fi

print_section "Test 2: Frontend -> Database (should FAIL with policy)"
print_test "Frontend cannot directly reach database..."
if kubectl -n cilium-demo exec "$FRONTEND_POD" -- wget -qO- --timeout=5 http://database 2>/dev/null | head -1 > /dev/null 2>&1; then
    print_fail "Frontend -> Database: Connection allowed (policy not enforced)"
else
    print_pass "Frontend -> Database: Connection blocked by policy"
fi

print_section "Test 3: Backend -> Database (should SUCCEED)"
print_test "Backend-api can reach database on port 80..."
if kubectl -n cilium-demo exec "$BACKEND_POD" -- wget -qO- --timeout=5 http://database 2>/dev/null | head -1 > /dev/null 2>&1; then
    print_pass "Backend -> Database: Connection allowed"
else
    print_fail "Backend -> Database: Connection blocked (unexpected)"
fi

print_section "Test 4: Cilium Endpoint Status"
print_test "Checking Cilium endpoint health..."
ENDPOINTS=$(kubectl -n cilium-demo get cep --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_ENDPOINTS=$(kubectl -n cilium-demo get cep --no-headers 2>/dev/null | grep -c "ready" || true)
echo "  Endpoints: $ENDPOINTS total, $READY_ENDPOINTS ready"

if [ "$ENDPOINTS" -gt 0 ]; then
    print_pass "Cilium endpoints are configured"
else
    print_fail "No Cilium endpoints found"
fi

print_section "Test 5: Network Policy Enforcement"
print_test "Checking Cilium network policies..."
POLICIES=$(kubectl -n cilium-demo get cnp --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  Active CiliumNetworkPolicies: $POLICIES"

if [ "$POLICIES" -ge 2 ]; then
    print_pass "Network policies are applied"
else
    print_fail "Expected at least 2 network policies"
fi

echo ""
echo "=========================================="
echo "   Test Summary"
echo "=========================================="
echo ""
echo "If all tests passed, Cilium CNI and network"
echo "policies are working correctly on your AKS cluster."
echo ""
echo "To see live traffic flows, use Hubble:"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &"
echo "  hubble observe -n cilium-demo --follow"
echo ""
