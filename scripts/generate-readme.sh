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
    Kubernetes) ((k8s_count++)) ;;
    Docker) ((docker_count++)) ;;
    Azure) ((azure_count++)) ;;
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
