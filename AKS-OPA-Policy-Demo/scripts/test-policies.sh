#!/usr/bin/env bash
#
# Applies the good/bad sample pods against the cluster and reports the result.
# With EFFECT=audit (the default in deploy.sh), all pods will be admitted but
# violations will show up as non-compliant resources in Azure Policy / Defender
# for Cloud and in `kubectl get <constraint> -o yaml`. With EFFECT=deny, the
# Gatekeeper admission webhook actively rejects the "bad-*" pods below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
EFFECT="${EFFECT:-audit}"

if [[ "$EFFECT" != "audit" && "$EFFECT" != "deny" ]]; then
  echo -e "${RED}EFFECT must be 'audit' or 'deny' (got '$EFFECT')${NC}"
  exit 1
fi

echo -e "${GREEN}== Applying compliant pod (expected: created) ==${NC}"
kubectl apply -f sample-apps/good-pod.yaml

echo ""
echo -e "${GREEN}== Applying violating pods (expected: created if audit, rejected if deny) ==${NC}"
for f in sample-apps/bad-pod-*.yaml; do
  echo -e "${YELLOW}-- $f --${NC}"
  if kubectl apply -f "$f"; then
    if [[ "$EFFECT" == "deny" ]]; then
      echo -e "${RED}Expected this pod to be rejected in deny mode, but it was admitted.${NC}"
      exit 1
    fi
    echo -e "${GREEN}Admitted (expected in audit mode).${NC}"
  else
    if [[ "$EFFECT" == "deny" ]]; then
      echo -e "${GREEN}Rejected by admission webhook (expected in deny mode).${NC}"
    else
      echo -e "${RED}kubectl apply failed unexpectedly in audit mode.${NC}"
      exit 1
    fi
  fi
  echo ""
done

echo -e "${GREEN}== Gatekeeper constraint templates synced by the Azure Policy add-on ==${NC}"
kubectl get constrainttemplates | grep -i k8sazure || true

echo ""
echo -e "${GREEN}== Constraint violations (audit results, may take a few minutes to populate) ==${NC}"
for ct in $(kubectl get constrainttemplates -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  KIND=$(kubectl get constrainttemplate "$ct" -o jsonpath='{.spec.crd.spec.names.kind}')
  echo -e "${YELLOW}-- $KIND --${NC}"
  kubectl get "$KIND" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.totalViolations}{"\n"}{end}' 2>/dev/null || true
done

echo ""
echo "To clean up the sample pods: kubectl delete -f sample-apps/ -n workloads --ignore-not-found"
