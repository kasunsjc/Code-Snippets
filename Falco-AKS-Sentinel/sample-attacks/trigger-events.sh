#!/bin/bash
set -euo pipefail

# Triggers a handful of Falco rule violations inside the falco-attack pod.
# Run AFTER `kubectl apply -f sample-attacks/attack-pod.yaml`.

POD="${POD:-falco-attack}"

echo "==> Waiting for pod $POD to be Ready..."
kubectl wait --for=condition=Ready "pod/$POD" --timeout=120s

echo "==> [1/4] Read sensitive file (/etc/shadow)"
kubectl exec "$POD" -- sh -c 'cat /etc/shadow > /dev/null' || true

echo "==> [2/4] Write below /etc (modify /etc/hosts)"
kubectl exec "$POD" -- sh -c 'echo "127.0.0.1 evil.local" >> /etc/hosts' || true

echo "==> [3/4] Spawn a shell-in-container event"
kubectl exec "$POD" -- sh -c 'sh -c "id; uname -a"' || true

echo "==> [4/4] Run a package manager inside the container"
kubectl exec "$POD" -- sh -c 'apk add --no-cache curl >/dev/null 2>&1 || true'

echo ""
echo "==> Done. Check Falco logs:"
echo "    kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=100 | grep -i warning"
echo ""
echo "==> Check falcosidekick-ui:"
echo "    kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802"
echo "    # then open http://localhost:2802"
echo ""
echo "==> Wait 2-5 minutes, then check Sentinel:"
echo "    Sentinel → Logs → FalcoAlerts_CL | take 50"
echo "    Sentinel → Incidents (created by 'Falco — Runtime Security Alert (AKS)' rule)"
