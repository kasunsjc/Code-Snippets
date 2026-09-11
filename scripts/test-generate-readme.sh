#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_REPO="$TMP_DIR/repo"
mkdir -p "$TEST_REPO/scripts" \
         "$TEST_REPO/AKS-ArgoCD-Extension" \
         "$TEST_REPO/AKS-Harbor-Registry-Demo" \
         "$TEST_REPO/BYO-CNI-AKS"

cp "$REPO_ROOT/scripts/generate-readme.sh" "$TEST_REPO/scripts/generate-readme.sh"
cp "$REPO_ROOT/scripts/generate_blog_mappings.py" "$TEST_REPO/scripts/generate_blog_mappings.py"
chmod +x "$TEST_REPO/scripts/generate-readme.sh"

cat > "$TEST_REPO/AKS-ArgoCD-Extension/README.md" <<'EOF'
# AKS Argo CD Extension with Microsoft Entra SSO
Sample Argo CD extension demo.
EOF

cat > "$TEST_REPO/BYO-CNI-AKS/README.md" <<'EOF'
# BYO CNI on AKS with Cilium
Sample BYO CNI demo.
EOF

cat > "$TEST_REPO/AKS-Harbor-Registry-Demo/README.md" <<'EOF'
# Harbor on AKS — Terraform + Traefik + cert-manager + Azure DNS

- [Harbor Audit Logs in Azure Log Analytics: A Fluent Bit Bridge](https://kasunrajapakse.me/blog/harbor-audit-logs-azure-log-analytics/)
- [Monitoring Harbor with Azure Monitor and Azure Managed Grafana](https://kasunrajapakse.me/blog/monitor-harbor-azure-monitor-managed-grafana/)
- [Harbor Audit Logs duplicate](https://kasunrajapakse.me/blog/harbor-audit-logs-azure-log-analytics/?utm=test#section)
EOF

bash "$TEST_REPO/scripts/generate-readme.sh"

grep -Fq "Deploying the AKS Argo CD Extension with App Routing Ingress and Entra ID SSO" "$TEST_REPO/README.md"
grep -Fq "[BYO CNI on AKS with Cilium](./BYO-CNI-AKS/)" "$TEST_REPO/README.md"

harbor_count="$(grep -Fc "| [Harbor Audit Logs in Azure Log Analytics: A Fluent Bit Bridge](https://kasunrajapakse.me/blog/harbor-audit-logs-azure-log-analytics/) | [Harbor on AKS — Terraform + Traefik + cert-manager + Azure DNS](./AKS-Harbor-Registry-Demo/) |" "$TEST_REPO/README.md")"
if [[ "$harbor_count" -ne 1 ]]; then
  echo "Expected Harbor audit log blog to appear once, found $harbor_count" >&2
  exit 1
fi

cat > "$TMP_DIR/feed.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <item>
      <title>Harbor OIDC with Azure Monitor and Grafana</title>
      <link>https://kasunrajapakse.me/blog/harbor-oidc-azure-monitor-grafana/</link>
      <description>Harbor with oidc, azure monitor, grafana, and log analytics on AKS.</description>
    </item>
    <item>
      <title>Different Harbor Audit Title</title>
      <link>https://kasunrajapakse.me/blog/harbor-audit-logs-azure-log-analytics/?ref=feed</link>
      <description>Harbor log analytics duplicate.</description>
    </item>
  </channel>
</rss>
EOF

ENABLE_BLOG_DISCOVERY=1 BLOG_FEED_FIXTURE="$TMP_DIR/feed.xml" bash "$TEST_REPO/scripts/generate-readme.sh"
grep -Fq "https://kasunrajapakse.me/blog/harbor-oidc-azure-monitor-grafana/" "$TEST_REPO/README.md"
grep -Fq "[Harbor Audit Logs in Azure Log Analytics: A Fluent Bit Bridge](https://kasunrajapakse.me/blog/harbor-audit-logs-azure-log-analytics/)" "$TEST_REPO/README.md"

echo "README generator tests passed"
