#!/usr/bin/env python3

import os
import re
import socket
import sys
import xml.etree.ElementTree as ET
from html import escape
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
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


def main():
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
        return 0

    print("## 📝 Related Blog Posts\n")
    print("Looking for the full walkthroughs behind some of these samples? Visit the")
    print(f"[Kasun Rajapakse blog]({BLOG_HOME}) for the companion")
    print("articles linked below.\n")
    print("| Blog Post | Code Sample |")
    print("|---|---|")
    for example_name, example_title, blog_title, blog_url in sorted(rows, key=lambda row: (row[0].lower(), row[3].lower(), row[2].lower())):
        print(f"| [{escape(blog_title)}]({blog_url}) | [{escape(example_title)}](./{example_name}/) |")
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
