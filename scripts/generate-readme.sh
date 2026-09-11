#!/bin/bash
# generate-readme.sh
# Scans all top-level example directories and regenerates the root README.md
# with an auto-generated table of contents and example catalog.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$REPO_ROOT/README.md"

# Directories and files to skip
SKIP_DIRS=(".git" ".github" "scripts" "node_modules" ".DS_Store")

# Categorize examples based on folder name patterns
categorize() {
  local dir="$1"
  case "$dir" in
    AKS-*|Agentic-CLI-AKS|BYO-CNI-AKS|Custom-AKS-Copilot-Agent|Platform-Enginering-AKS-ArgoCD-ASO)
      echo "Kubernetes"
      ;;
    Docker-*)
      echo "Docker"
      ;;
    ACR-*)
      echo "Azure"
      ;;
    *)
      echo "Other"
      ;;
  esac
}

# Extract title from a README.md (first H1 heading)
get_title() {
  local readme="$1"
  if [[ -f "$readme" ]]; then
    grep -m1 '^# ' "$readme" | sed 's/^# //' | sed 's/ *$//'
  else
    echo ""
  fi
}

# Extract description from a README.md (first non-empty line after first heading)
get_description() {
  local readme="$1"
  if [[ -f "$readme" ]]; then
    awk '/^# /{found=1; next} found && /^[^#]/ && NF{print; exit}' "$readme" | sed 's/^ *//'
  else
    echo "No description available"
  fi
}

# Emit personal blog mappings for demos that have a matching walkthrough
emit_blog_mappings() {
  cat <<'EOF'
## 📝 Related Blog Posts

Looking for the full walkthroughs behind some of these samples? Visit the
[Kasun Rajapakse blog](https://kasunrajapakse.me/blog/) for the companion
articles linked below.

| Blog Post | Code Sample |
|---|---|
| [Advanced Container Networking Services on AKS: X-Ray Vision and Kernel-Level Guardrails for Your Cluster Network](https://kasunrajapakse.me/blog/aks-advanced-container-networking-services/) | [AKS-ACNS-Cilium-Terraform](./AKS-ACNS-Cilium-Terraform/) |
| [Deploying the AKS Argo CD Extension with App Routing Ingress and Entra ID SSO](https://kasunrajapakse.me/blog/aks-argo-cd-extension-app-routing-entra-id-sso) | [AKS-ArgoCD-Extension](./AKS-ArgoCD-Extension/) |
| [Migrating AKS Ingress to Istio-Based Gateway API: Moving Beyond NGINX](https://kasunrajapakse.me/blog/aks-istio-gateway-api/) | [AKS-Istio-Gateway-API](./AKS-Istio-Gateway-API/) |
| [Scaling AKS Workloads on Custom Metrics with KEDA and Azure Managed Prometheus](https://kasunrajapakse.me/blog/aks-keda-managed-prometheus-scaler/) | [AKS-KEDA-Demo](./AKS-KEDA-Demo/) |
| [Advanced Container Networking Services on AKS: X-Ray Vision and Kernel-Level Guardrails for Your Cluster Network](https://kasunrajapakse.me/blog/aks-advanced-container-networking-services/) | [BYO-CNI-AKS](./BYO-CNI-AKS/) |
| [How to store Harbor audit logs in Azure Log Analytics](https://kasunrajapakse.me/blog/harbor-audit-logs-azure-log-analytics/) | [AKS-Harbor-Registry-Demo](./AKS-Harbor-Registry-Demo/) |
| [Monitoring Harbor with Azure Monitor and Azure Managed Grafana](https://kasunrajapakse.me/blog/monitor-harbor-azure-monitor-managed-grafana/) | [AKS-Harbor-Registry-Demo](./AKS-Harbor-Registry-Demo/) |
| [Runtime Threat Detection on AKS with Falco and Microsoft Sentinel](https://kasunrajapakse.me/blog/falco-aks-sentinel-runtime-security/) | [Falco-AKS-Sentinel](./Falco-AKS-Sentinel/) |
| [Why You Should Never Lock AKS-Managed Resources: A Volume Outage Story](https://kasunrajapakse.me/blog/aks-resource-locks-managed-disks-incident/) | [AKS-NodeRG-Lockdown](./AKS-NodeRG-Lockdown/) |

EOF
}

# Collect all example directories
declare -a EXAMPLES=()
for dir in "$REPO_ROOT"/*/; do
  dirname="$(basename "$dir")"

  # Skip non-example directories
  skip=false
  for s in "${SKIP_DIRS[@]}"; do
    if [[ "$dirname" == "$s" ]]; then
      skip=true
      break
    fi
  done
  $skip && continue

  # Must be a directory (not a file)
  [[ -d "$dir" ]] || continue

  EXAMPLES+=("$dirname")
done

# Sort examples
IFS=$'\n' EXAMPLES=($(sort <<<"${EXAMPLES[*]}")); unset IFS

# Count stats
total=${#EXAMPLES[@]}
k8s_count=0; docker_count=0; azure_count=0
for ex in "${EXAMPLES[@]}"; do
  cat=$(categorize "$ex")
  case "$cat" in
    Kubernetes) ((++k8s_count)) ;;
    Docker) ((++docker_count)) ;;
    Azure) ((++azure_count)) ;;
  esac
done

# Generate README
cat > "$README" << 'HEADER'
# Code Snippets Repository 🚀

Welcome to the **Code Snippets Repository**! This repository contains sample code, demos, and tutorials for Azure Kubernetes Service (AKS), Docker, and container technologies. Perfect for learning, blog posts, and YouTube tutorials.

<!-- AUTO-GENERATED CONTENT BELOW - DO NOT EDIT MANUALLY -->
<!-- Last updated by GitHub Actions -->

HEADER

# Stats badge
current_date=$(date +"%B %Y")
cat >> "$README" << EOF
> **${total} examples** | Kubernetes: ${k8s_count} | Docker: ${docker_count} | Azure: ${azure_count} | *Last Updated: ${current_date}*

EOF

emit_blog_mappings >> "$README"

cat >> "$README" << EOF
## 📋 Table of Contents

| # | Demo | Description | Category |
|---|------|-------------|----------|
EOF

# Generate table rows
i=1
for ex in "${EXAMPLES[@]}"; do
  readme_path="$REPO_ROOT/$ex/README.md"
  title=$(get_title "$readme_path")
  desc=$(get_description "$readme_path")
  category=$(categorize "$ex")

  # Fallback title to directory name
  if [[ -z "$title" ]]; then
    title="$ex"
  fi

  # Truncate long descriptions
  if [[ ${#desc} -gt 100 ]]; then
    desc="${desc:0:97}..."
  fi

  echo "| ${i} | [${ex}](./${ex}/) | ${desc} | ${category} |" >> "$README"
  ((i++))
done

# Category sections
cat >> "$README" << 'EOF'

---

## 📁 Examples by Category

EOF

for category in "Kubernetes" "Docker" "Azure" "Other"; do
  has_items=false
  for ex in "${EXAMPLES[@]}"; do
    if [[ "$(categorize "$ex")" == "$category" ]]; then
      has_items=true
      break
    fi
  done
  $has_items || continue

  cat >> "$README" << EOF
### ${category}

EOF

  for ex in "${EXAMPLES[@]}"; do
    if [[ "$(categorize "$ex")" == "$category" ]]; then
      readme_path="$REPO_ROOT/$ex/README.md"
      title=$(get_title "$readme_path")
      desc=$(get_description "$readme_path")
      [[ -z "$title" ]] && title="$ex"

      has_readme="No"
      [[ -f "$readme_path" ]] && has_readme="Yes"

      # Count files
      file_count=$(find "$REPO_ROOT/$ex" -type f | wc -l | tr -d ' ')

      cat >> "$README" << EOF
- **[${ex}](./${ex}/)** — ${desc}
  - 📄 README: ${has_readme} | 📁 Files: ${file_count}
EOF
    fi
  done

  echo "" >> "$README"
done

# Footer
cat >> "$README" << 'EOF'
---

## 🛠️ Prerequisites

### General Requirements
- **Azure CLI** (latest version)
- **kubectl** (v1.28+)
- **Docker Desktop** (v4.27+ for basic, v4.50+ for sandboxes)
- **Azure Subscription** with appropriate permissions

### Optional Tools
- **Bicep CLI** (for template editing)
- **cosign** (for signature verification)
- **Helm** (for chart deployments)

## 🚀 Getting Started

1. **Clone the repository:**
   ```bash
   git clone https://github.com/kasunsjc/Code-Snippets.git
   cd Code-Snippets
   ```

2. **Navigate to a demo folder:**
   ```bash
   cd <example-folder>
   ```

3. **Follow the README or scripts in each folder**

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests to improve these demos.

## 📄 License

This repository is provided for educational purposes. See the [LICENSE](./LICENSE) file for details.

---

<!-- AUTO-GENERATED CONTENT ABOVE - DO NOT EDIT MANUALLY -->
EOF

echo "✅ README.md updated with ${total} examples"
