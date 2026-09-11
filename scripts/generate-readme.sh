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
  REPO_ROOT="$REPO_ROOT" python3 <<'PY'
import os
import re
import socket
import sys
import xml.etree.ElementTree as ET
from html import escape
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit, urlunsplit
from urllib.request import Request, urlopen

REPO_ROOT = Path(os.environ["REPO_ROOT"])
BLOG_HOME = "https://kasunrajapakse.me/blog/"
ENABLE_BLOG_DISCOVERY = os.environ.get("ENABLE_BLOG_DISCOVERY", "0") == "1"
BLOG_FEED_FIXTURE = os.environ.get("BLOG_FEED_FIXTURE", "").strip()
SKIP_DIRS = {".git", ".github", "scripts", "node_modules", ".DS_Store"}
BLOG_URL_RE = re.compile(r"\[([^\]]+)\]\((https://kasunrajapakse\.me/[^)\s]+)\)")
HEADING_RE = re.compile(r"^#\s+(.+)$", re.MULTILINE)
NON_POST_PATHS = ("/tags/", "/page/", "/categories/", "/authors/")

SEEDED_BLOG_MAPPINGS = {
    "AKS-ACNS-Cilium-Terraform": [
        ("Advanced Container Networking Services on AKS: X-Ray Vision and Kernel-Level Guardrails for Your Cluster Network", "https://kasunrajapakse.me/blog/aks-advanced-container-networking-services/"),
    ],
    "AKS-ArgoCD-Extension": [
        ("Deploying the AKS Argo CD Extension with App Routing Ingress and Entra ID SSO", "https://kasunrajapakse.me/blog/aks-argo-cd-extension-app-routing-entra-id-sso"),
    ],
    "AKS-Istio-Gateway-API": [
        ("Migrating AKS Ingress to Istio-Based Gateway API: Moving Beyond NGINX", "https://kasunrajapakse.me/blog/aks-istio-gateway-api/"),
    ],
    "AKS-KEDA-Demo": [
        ("Scaling AKS Workloads on Custom Metrics with KEDA and Azure Managed Prometheus", "https://kasunrajapakse.me/blog/aks-keda-managed-prometheus-scaler/"),
    ],
    "BYO-CNI-AKS": [
        ("Advanced Container Networking Services on AKS: X-Ray Vision and Kernel-Level Guardrails for Your Cluster Network", "https://kasunrajapakse.me/blog/aks-advanced-container-networking-services/"),
    ],
    "Falco-AKS-Sentinel": [
        ("Runtime Threat Detection on AKS with Falco and Microsoft Sentinel", "https://kasunrajapakse.me/blog/falco-aks-sentinel-runtime-security/"),
    ],
    "AKS-NodeRG-Lockdown": [
        ("Why You Should Never Lock AKS-Managed Resources: A Volume Outage Story", "https://kasunrajapakse.me/blog/aks-resource-locks-managed-disks-incident/"),
    ],
}

DISCOVERY_HINTS = {
    "AKS-ACNS-Cilium-Terraform": ["advanced container networking services", "aks", "cilium"],
    "AKS-ArgoCD-Extension": ["argo cd extension", "app routing", "entra id", "sso"],
    "AKS-Harbor-Registry-Demo": ["harbor", "azure monitor", "grafana", "log analytics", "oidc"],
    "AKS-Istio-Gateway-API": ["istio", "gateway api", "ingress"],
    "AKS-KEDA-Demo": ["keda", "managed prometheus", "autoscaling"],
    "BYO-CNI-AKS": ["byo cni", "cilium", "bring your own cni"],
    "Falco-AKS-Sentinel": ["falco", "sentinel", "runtime threat"],
    "AKS-NodeRG-Lockdown": ["aks-managed resources", "resource locks", "volume outage"],
}

FEED_URLS = [
    "https://kasunrajapakse.me/blog/index.xml",
    "https://kasunrajapakse.me/index.xml",
    "https://kasunrajapakse.me/feed/",
    "https://kasunrajapakse.me/feed",
]

SOURCE_PRIORITIES = {
    "seeded": 0,
    "readme": 1,
    "discovery": 2,
}


def normalize(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def canonicalize_url(url: str) -> str:
    url = url.strip()
    if not url.startswith("https://kasunrajapakse.me/"):
        return url
    parts = urlsplit(url)
    normalized_path = parts.path.rstrip("/") + "/"
    return urlunsplit((parts.scheme, parts.netloc, normalized_path, "", ""))


def iter_examples():
    for path in sorted(REPO_ROOT.iterdir(), key=lambda p: p.name.lower()):
        if not path.is_dir() or path.name in SKIP_DIRS:
            continue
        readme_path = path / "README.md"
        title = path.name
        if readme_path.exists():
            text = readme_path.read_text(encoding="utf-8", errors="ignore")
            match = HEADING_RE.search(text)
            if match:
                title = match.group(1).strip()
        yield path.name, title, readme_path


def is_blog_post_url(url: str) -> bool:
    url = canonicalize_url(url)
    if not url.startswith("https://kasunrajapakse.me/"):
        return False
    if url.rstrip("/") == BLOG_HOME.rstrip("/"):
        return False
    return not any(marker in url for marker in NON_POST_PATHS)


def extract_blog_links(readme_path: Path):
    if not readme_path.exists():
        return []
    text = readme_path.read_text(encoding="utf-8", errors="ignore")
    links = []
    seen = set()
    for title, url in BLOG_URL_RE.findall(text):
        url = canonicalize_url(url)
        if not is_blog_post_url(url):
            continue
        key = url.rstrip("/")
        if key in seen:
            continue
        seen.add(key)
        links.append((title.strip(), url.strip()))
    return links


def parse_feed_payload(payload):
    try:
        root = ET.fromstring(payload)
    except ET.ParseError:
        return []

    posts = []
    for item in root.findall(".//item") + root.findall(".//{*}entry"):
        title = (item.findtext("title") or item.findtext("{*}title") or "").strip()
        link = (item.findtext("link") or item.findtext("{*}link") or "").strip()
        if not is_blog_post_url(link):
            alternate_links = []
            fallback_links = []
            for link_element in item.findall("{*}link"):
                href = (link_element.attrib.get("href") or link_element.attrib.get("url") or "").strip()
                rel = (link_element.attrib.get("rel") or "").strip().lower()
                if not href:
                    continue
                if rel in ("", "alternate"):
                    alternate_links.append(href)
                else:
                    fallback_links.append(href)
            for candidate in alternate_links + fallback_links:
                if is_blog_post_url(candidate):
                    link = candidate
                    break
        summary = " ".join(
            part.strip()
            for part in [
                item.findtext("description"),
                item.findtext("{*}description"),
                item.findtext("{http://purl.org/rss/1.0/modules/content/}encoded"),
                item.findtext("{*}content"),
                item.findtext("{*}summary"),
            ]
            if part and part.strip()
        )
        link = canonicalize_url(link)
        if title and is_blog_post_url(link):
            posts.append({"title": title, "url": link, "text": normalize(f"{title} {link} {summary}")})
    return posts


def fetch_feed_posts():
    if BLOG_FEED_FIXTURE:
        try:
            return parse_feed_payload(Path(BLOG_FEED_FIXTURE).read_bytes())
        except OSError:
            return []

    if not ENABLE_BLOG_DISCOVERY:
        return []

    for feed_url in FEED_URLS:
        try:
            request = Request(feed_url, headers={"User-Agent": "Code-Snippets README Generator"})
            with urlopen(request, timeout=10) as response:
                payload = response.read()
        except (HTTPError, URLError, socket.timeout, TimeoutError, OSError, ValueError):
            continue

        posts = parse_feed_payload(payload)
        if posts:
            return posts

    return []


def discover_matches(example_name: str, feed_posts):
    hints = [normalize(hint) for hint in DISCOVERY_HINTS.get(example_name, []) if hint.strip()]
    if not hints:
        return []

    discovered = []
    for post in feed_posts:
        matches = sum(1 for hint in hints if hint in post["text"])
        if matches >= 2 or (matches >= 1 and len(hints) == 1):
            discovered.append((post["title"], post["url"]))
    return discovered


def add_links(bucket, links, source):
    priority = SOURCE_PRIORITIES[source]
    for title, url in links:
        url = canonicalize_url(url)
        key = url.rstrip("/")
        current = bucket.get(key)
        if current is not None and current["priority"] <= priority:
            continue
        bucket[key] = {"priority": priority, "title": title.strip(), "url": url}


feed_posts = fetch_feed_posts()
rows = []
for example_name, example_title, readme_path in iter_examples():
    links = {}
    add_links(links, SEEDED_BLOG_MAPPINGS.get(example_name, []), "seeded")
    add_links(links, extract_blog_links(readme_path), "readme")
    add_links(links, discover_matches(example_name, feed_posts), "discovery")

    for link in links.values():
        rows.append((example_name, example_title, link["title"], link["url"]))

if not rows:
    sys.exit(0)

print("## 📝 Related Blog Posts\n")
print("Looking for the full walkthroughs behind some of these samples? Visit the")
print(f"[Kasun Rajapakse blog]({BLOG_HOME}) for the companion")
print("articles linked below.\n")
print("| Blog Post | Code Sample |")
print("|---|---|")
for example_name, example_title, blog_title, blog_url in sorted(rows, key=lambda row: (row[0].lower(), row[3].lower(), row[2].lower())):
    print(f"| [{escape(blog_title)}]({blog_url}) | [{escape(example_title)}](./{quote(example_name, safe='/')}/) |")
print()
PY
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
