#!/usr/bin/env bash
# =============================================================================
# test-policies.sh - Interactive Kyverno Policy Demo Script
# =============================================================================
# This script walks through each Kyverno policy scenario, showing
# expected outcomes (ALLOW/BLOCK/MUTATE/GENERATE) with clear output.
# Run this after deploy.sh has completed successfully.
# =============================================================================
set -e

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_NS="demo"
PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════${NC}"
}

print_step() {
  echo ""
  echo -e "${CYAN}▶ $1${NC}"
}

expect_blocked() {
  local manifest="$1"
  local description="$2"
  print_step "TEST (expect BLOCKED): $description"
  if kubectl apply -f "$manifest" --dry-run=server 2>&1 | grep -q "denied\|Error\|failed"; then
    echo -e "  ${GREEN}✔ PASS${NC} — Kyverno correctly blocked the request."
    ((PASS++))
  else
    echo -e "  ${RED}✘ FAIL${NC} — Request was NOT blocked. Check the policy."
    ((FAIL++))
  fi
}

expect_allowed() {
  local manifest="$1"
  local description="$2"
  print_step "TEST (expect ALLOWED): $description"
  if kubectl apply -f "$manifest" --dry-run=server 2>&1 | grep -qv "denied\|Error\|failed"; then
    echo -e "  ${GREEN}✔ PASS${NC} — Kyverno correctly allowed the request."
    ((PASS++))
  else
    echo -e "  ${RED}✘ FAIL${NC} — Request was unexpectedly denied. Check the manifest."
    ((FAIL++))
  fi
}

wait_for_resource() {
  local kind="$1"
  local name="$2"
  local ns="$3"
  local max_wait=30
  local count=0
  while ! kubectl get "$kind" "$name" -n "$ns" &>/dev/null; do
    ((count++))
    if [[ $count -ge $max_wait ]]; then
      return 1
    fi
    sleep 1
  done
  return 0
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
print_header "Pre-flight Checks"

print_step "Verifying kubectl is configured..."
kubectl cluster-info --request-timeout=5s >/dev/null
echo -e "  ${GREEN}✔${NC} kubectl connected."

print_step "Verifying Kyverno is running..."
KYVERNO_READY=$(kubectl get pods -n kyverno -l app.kubernetes.io/name=kyverno-admission-controller \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$KYVERNO_READY" -ge "1" ]]; then
  echo -e "  ${GREEN}✔${NC} Kyverno admission controller is running ($KYVERNO_READY replica(s))."
else
  echo -e "  ${RED}✘${NC} Kyverno is not running. Run deploy.sh first."
  exit 1
fi

print_step "Ensuring demo namespace exists..."
kubectl get namespace "$DEMO_NS" &>/dev/null || kubectl create namespace "$DEMO_NS"
echo -e "  ${GREEN}✔${NC} Namespace '$DEMO_NS' is ready."

print_step "Listing active Kyverno policies..."
echo ""
kubectl get clusterpolicies 2>/dev/null || echo "  (no ClusterPolicies found)"
kubectl get clustercleanuppolicies 2>/dev/null || true

# ── Section 1: Validation ────────────────────────────────────────────────────
print_header "Section 1: Validation Policies"

expect_allowed \
  "$SCRIPT_DIR/01-compliant-pod.yaml" \
  "Compliant pod (should be allowed)"

expect_blocked \
  "$SCRIPT_DIR/02-non-compliant-privileged.yaml" \
  "Privileged container (disallow-privileged-containers)"

expect_blocked \
  "$SCRIPT_DIR/03-non-compliant-no-limits.yaml" \
  "Missing resource limits (require-resource-limits)"

expect_blocked \
  "$SCRIPT_DIR/04-non-compliant-latest-tag.yaml" \
  "Image tagged :latest (disallow-latest-tag)"

expect_blocked \
  "$SCRIPT_DIR/05-non-compliant-missing-labels.yaml" \
  "Missing required labels (require-pod-labels)"

# ── Section 2: Mutation ──────────────────────────────────────────────────────
print_header "Section 2: Mutation Policies"

print_step "Applying mutation test pod..."
kubectl apply -f "$SCRIPT_DIR/06-mutation-test-pod.yaml" -n "$DEMO_NS" 2>/dev/null || \
  kubectl delete pod mutation-test -n "$DEMO_NS" --ignore-not-found && \
  kubectl apply -f "$SCRIPT_DIR/06-mutation-test-pod.yaml"

print_step "Waiting for pod to be created..."
if wait_for_resource pod mutation-test "$DEMO_NS"; then
  echo ""
  echo -e "  ${GREEN}✔${NC} Pod created. Verifying mutations..."
  echo ""

  echo -e "  ${YELLOW}Labels on mutation-test pod:${NC}"
  kubectl get pod mutation-test -n "$DEMO_NS" -o jsonpath='{.metadata.labels}' | \
    python3 -m json.tool 2>/dev/null || \
    kubectl get pod mutation-test -n "$DEMO_NS" -o jsonpath='{.metadata.labels}'
  echo ""

  echo -e "  ${YELLOW}Annotations on mutation-test pod:${NC}"
  kubectl get pod mutation-test -n "$DEMO_NS" -o jsonpath='{.metadata.annotations}' | \
    python3 -m json.tool 2>/dev/null || \
    kubectl get pod mutation-test -n "$DEMO_NS" -o jsonpath='{.metadata.annotations}'
  echo ""

  echo -e "  ${YELLOW}Security context after mutation:${NC}"
  kubectl get pod mutation-test -n "$DEMO_NS" \
    -o jsonpath='{.spec.containers[0].securityContext}' | \
    python3 -m json.tool 2>/dev/null || \
    kubectl get pod mutation-test -n "$DEMO_NS" \
    -o jsonpath='{.spec.containers[0].securityContext}'
  echo ""

  # Check mutation-related labels
  MANAGED_BY=$(kubectl get pod mutation-test -n "$DEMO_NS" \
    -o jsonpath='{.metadata.labels.managed-by}' 2>/dev/null)
  if [[ "$MANAGED_BY" == "kyverno" ]]; then
    echo -e "  ${GREEN}✔ PASS${NC} — 'managed-by=kyverno' label was mutated in."
    ((PASS++))
  else
    echo -e "  ${RED}✘ FAIL${NC} — Expected 'managed-by=kyverno' label not found."
    ((FAIL++))
  fi
else
  echo -e "  ${RED}✘${NC} Timed out waiting for pod."
  ((FAIL++))
fi

# ── Section 3: Generation ────────────────────────────────────────────────────
print_header "Section 3: Generation Policies"

print_step "Creating test namespace to trigger generation policies..."
kubectl apply -f "$SCRIPT_DIR/07-generation-test-namespace.yaml"

print_step "Waiting for generated NetworkPolicies..."
sleep 5

echo ""
echo -e "  ${YELLOW}NetworkPolicies in 'kyverno-demo-ns':${NC}"
kubectl get networkpolicy -n kyverno-demo-ns 2>/dev/null || echo "  (none found yet)"

echo ""
echo -e "  ${YELLOW}ResourceQuotas in 'kyverno-demo-ns':${NC}"
kubectl get resourcequota -n kyverno-demo-ns 2>/dev/null || echo "  (none found yet)"

DENY_NP=$(kubectl get networkpolicy default-deny-ingress -n kyverno-demo-ns &>/dev/null && echo "yes" || echo "no")
QUOTA=$(kubectl get resourcequota default-quota -n kyverno-demo-ns &>/dev/null && echo "yes" || echo "no")

if [[ "$DENY_NP" == "yes" ]]; then
  echo -e "  ${GREEN}✔ PASS${NC} — NetworkPolicy 'default-deny-ingress' was generated."
  ((PASS++))
else
  echo -e "  ${RED}✘ FAIL${NC} — NetworkPolicy 'default-deny-ingress' not found."
  ((FAIL++))
fi

if [[ "$QUOTA" == "yes" ]]; then
  echo -e "  ${GREEN}✔ PASS${NC} — ResourceQuota 'default-quota' was generated."
  ((PASS++))
else
  echo -e "  ${RED}✘ FAIL${NC} — ResourceQuota 'default-quota' not found."
  ((FAIL++))
fi

# ── Section 4: Policy Reports ─────────────────────────────────────────────────
print_header "Section 4: Kyverno Policy Reports"

print_step "Checking Policy Reports (background scan results)..."
echo ""
kubectl get policyreport -A 2>/dev/null || echo "  (no policy reports found yet — reports are generated asynchronously)"

echo ""
print_step "Checking ClusterPolicy Reports..."
kubectl get clusterpolicyreport 2>/dev/null || echo "  (no cluster policy reports yet)"

# ── Summary ──────────────────────────────────────────────────────────────────
print_header "Test Summary"
echo ""
TOTAL=$((PASS + FAIL))
echo -e "  Total tests : ${BOLD}$TOTAL${NC}"
echo -e "  Passed      : ${GREEN}${BOLD}$PASS${NC}"
echo -e "  Failed      : ${RED}${BOLD}$FAIL${NC}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All tests passed! Kyverno policies are working correctly.${NC}"
else
  echo -e "  ${YELLOW}Some tests failed. Review the output above and check policy status:${NC}"
  echo -e "  ${CYAN}kubectl describe clusterpolicy${NC}"
fi

echo ""
print_step "Useful commands for further exploration:"
echo ""
echo -e "  ${CYAN}# View all Kyverno policies${NC}"
echo -e "  kubectl get clusterpolicies"
echo ""
echo -e "  ${CYAN}# Describe a specific policy${NC}"
echo -e "  kubectl describe clusterpolicy disallow-privileged-containers"
echo ""
echo -e "  ${CYAN}# View admission webhook logs${NC}"
echo -e "  kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno-admission-controller --tail=50"
echo ""
echo -e "  ${CYAN}# View policy violation events${NC}"
echo -e "  kubectl get events -A --field-selector reason=PolicyViolation"
echo ""
echo -e "  ${CYAN}# View policy reports${NC}"
echo -e "  kubectl get policyreport -A"
echo ""
