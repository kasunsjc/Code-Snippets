# Docker Hardened Images (DHI) Demo 🔒

Welcome to this comprehensive demo on **Docker Hardened Images**! This repository demonstrates Docker's official hardened image solution and best practices for creating secure, production-ready container images.

> **Note**: Docker Hardened Images are now **FREE** for every developer with no subscription required, no usage restrictions, and licensed under Apache 2.0!

## 📋 Table of Contents

- [What are Docker Hardened Images?](#what-are-docker-hardened-images)
- [Why Use Docker Hardened Images?](#why-use-docker-hardened-images)
- [Key DHI Features](#key-dhi-features)
- [Demo Structure](#demo-structure)
- [Prerequisites](#prerequisites)
- [Running the Demo](#running-the-demo)
- [DHI vs Standard Images Comparison](#dhi-vs-standard-images-comparison)
- [Understanding DHI Concepts](#understanding-dhi-concepts)
- [Best Practices](#best-practices)
- [Additional Resources](#additional-resources)

## 🛡️ What are Docker Hardened Images?

**Docker Hardened Images (DHI)** are minimal, secure, and production-ready container base and application images **officially maintained by Docker**. They are designed to:
- Drastically reduce vulnerabilities (near-zero CVEs)
- Minimize attack surface by up to 95%
- Simplify compliance with industry standards
- Integrate seamlessly into existing Docker workflows

DHI images are built on a foundation of secure software supply chain practices and include:
- ✅ **SLSA Build Level 3** provenance
- ✅ **Signed SBOMs** (Software Bill of Materials)
- ✅ **VEX statements** (Vulnerability Exploitability eXchange)
- ✅ **Cryptographic signatures** for all images and metadata
- ✅ **Non-root execution** by default
- ✅ **Distroless and minimal variants**

### DHI Free vs DHI Enterprise

| Feature | DHI Free | DHI Enterprise |
|---------|----------|----------------|
| **Cost** | Free, Apache 2.0 | Subscription |
| **Near-zero CVEs** | ✅ | ✅ with SLA |
| **SLSA 3 + SBOMs** | ✅ | ✅ |
| **Minimal images** | ✅ | ✅ |
| **FIPS/STIG variants** | ❌ | ✅ |
| **Customization** | ❌ | ✅ |
| **Extended Lifecycle Support** | ❌ | ✅ Add-on |
| **CVE SLA** | No SLA | 7-day for Critical/High |

## 🎯 Why Use Docker Hardened Images?

### Security Risks of Non-Hardened Images:
1. **Large Attack Surface**: Standard images include hundreds of unnecessary packages
2. **High CVE Count**: 200+ known vulnerabilities in typical images
3. **Running as Root**: Elevated privileges can be exploited
4. **No Supply Chain Verification**: No SBOMs, provenance, or signatures
5. **Outdated Dependencies**: Manual patching required
6. **Large Image Size**: 400MB-1GB+ base images

### Benefits of Docker Hardened Images:
- ✅ **95% fewer vulnerabilities**: Near-zero CVEs maintained by Docker
- ✅ **90% smaller images**: 50MB vs 500MB+ (faster deployments, lower costs)
- ✅ **Complete transparency**: Signed SBOMs, provenance, and VEX statements
- ✅ **Automatic patching**: Continuous security updates from Docker
- ✅ **Compliance ready**: SLSA 3, FIPS, STIG, CIS benchmarks
- ✅ **Drop-in compatible**: Works with existing Docker workflows
- ✅ **Scanner integration**: Direct integration with Docker Scout and security platforms
- ✅ **Non-root by default**: Principle of least privilege

## 🔑 Key DHI Features

### 1. **Security by Default**
- **Near-zero CVEs**: Continuously scanned and patched
- **Minimal attack surface**: Distroless variants remove 95% of unnecessary components
- **Non-root execution**: Runs as non-root by default
- **Transparent vulnerability reporting**: Every CVE is visible (no suppressed feeds)

### 2. **Total Transparency**
Every DHI includes complete, verifiable security metadata:
- **SLSA Build Level 3 provenance**: Tamper-resistant, verifiable builds
- **Signed SBOMs**: Complete Software Bill of Materials
- **VEX statements**: Context about known CVEs and exploitability
- **Cryptographic signatures**: All images and metadata are signed

### 3. **Built for Developers**
- **Familiar foundations**: Built on Alpine and Debian
- **glibc and musl support**: Available in both variants
- **Dev and runtime variants**: Development images for building, minimal for production
- **Drop-in compatibility**: No retooling required

### 4. **Continuous Maintenance**
- **Automatic patching**: Images rebuilt when security patches are available
- **Scanner integration**: Works with Docker Scout, Trivy, Grype, Snyk
- **Registry integration**: Available at `dhi.io` and Docker Hub

### 5. **Kubernetes & Helm Support**
- **DHI Helm Charts**: Docker-provided charts optimized for DHI
- **OCI artifacts**: Available in DHI catalog on Docker Hub
- **SLSA Level 3 charts**: Complete provenance for charts
- **Hardened configuration**: Charts automatically reference DHI images

## � Understanding DHI Concepts

### 1. **SLSA (Supply-chain Levels for Software Artifacts)**
DHI images achieve **SLSA Build Level 3**, the highest level for build integrity:
- Verifiable build provenance
- Tamper-resistant builds
- Full audit trail from source to image

```bash
# View SLSA provenance
docker scout attestation dhi.io/python:3.13 --type provenance
```

### 2. **SBOM (Software Bill of Materials)**
Every DHI includes a cryptographically signed SBOM:
- Complete list of all software components
- Version information for every package
- License information
- Dependency relationships

```bash
# Export SBOM
docker scout sbom dhi.io/python:3.13 --format spdx > sbom.json
```

### 3. **VEX (Vulnerability Exploitability eXchange)**
VEX statements provide context about known CVEs:
- Which CVEs are actually exploitable
- Which are false positives
- Prioritize real risks

### 4. **Distroless Images**
DHI provides distroless variants that:
- Contain only your application and runtime dependencies
- Remove shell, package managers, and unnecessary binaries
- Reduce attack surface by 95%
- Make container breakouts much harder

### 5. **Image Immutability**
DHI ensures immutability through:
- **Digests**: Use SHA256 digests instead of tags
- **Signatures**: Cryptographic signatures prevent tampering
- **Read-only**: Can run containers in read-only mode

```bash
# Pull by digest for guaranteed immutability
docker pull dhi.io/python@sha256:abc123...
```

### 6. **Non-Root Execution**
All DHI images run as non-root by default:
- UID 65532 (nonroot user)
- Follows principle of least privilege
- Limits impact of container compromise

```bash
# Verify non-root execution
docker run --rm dhi.io/python:3.13 id
# Output: uid=65532(nonroot) gid=65532(nonroot)
```

### 7. **Compliance Standards**
DHI supports multiple compliance frameworks:
- **FIPS 140**: Validated cryptographic modules (Enterprise)
- **STIG**: DoD Security Technical Implementation Guide (Enterprise)
- **CIS Benchmarks**: Center for Internet Security standards
- **NIST**: National Institute of Standards and Technology

### 8. **Continuous Patching**
Docker automatically:
- Monitors for new CVEs
- Rebuilds images when patches available
- Updates SBOMs and provenance
- Maintains signed metadata

### 9. **glibc vs musl Variants**
DHI offers both:
- **glibc**: Better compatibility (based on Debian)
- **musl**: Smaller size, simpler (based on Alpine)

```
dhi.io/python:3.13-debian    # glibc variant
dhi.io/python:3.13-alpine    # musl variant
```

### 10. **Development vs Runtime Variants**
- **Dev variants**: Include build tools for compilation
- **Runtime variants**: Minimal, production-ready

```
dhi.io/python:3.13-dev       # For building
dhi.io/python:3.13           # For production
```

## 📁 Demo Structure

```
Docker-Hardened-Images/
├── README.md                          # This comprehensive guide
├── commands.sh                        # All demo commands to run
│
├── 01-standard-image/                 # BEFORE: Standard Docker image
│   ├── Dockerfile                     # Traditional Dockerfile
│   ├── app.py                         # Sample Python application
│   └── requirements.txt               # Python dependencies
│
├── 02-dhi-image/                      # AFTER: Using Docker Hardened Image
│   ├── Dockerfile.dhi                 # DHI-based Dockerfile
│   ├── app.py                         # Same application
│   └── requirements.txt               # Same dependencies
│
├── 03-dhi-advanced/                   # ADVANCED: Multi-stage with DHI
│   ├── Dockerfile.advanced            # Optimized multi-stage build
│   ├── app.py                         # Application
│   └── requirements.txt               # Dependencies
│
└── comparison/                        # Analysis and results
    ├── comparison-report.md          # Detailed comparison
    └── sbom-examples/                # SBOM samples
```

## 🔧 Prerequisites

- **Docker Desktop** installed (version 4.27+)
- **Docker Scout** CLI (included with Docker Desktop)
- **Docker Hub account** (free - to access DHI catalog)
- **Terminal** access (bash, zsh, or PowerShell)
- **cosign** (optional - for signature verification)

### Quick Check
```bash
docker --version
docker scout version
docker login dhi.io  # Login with your Docker ID
```

## 🚀 Running the Demo

### Part 1: Build Standard Image

```bash
# Navigate to standard image directory
cd 01-standard-image

# Build standard image
docker build -t demo-app:standard .

# Check image size and details
docker images demo-app:standard

# Scan for vulnerabilities
docker scout cves demo-app:standard

# Run the container
docker run -d -p 8001:8000 --name standard-app demo-app:standard

# Test the application
curl http://localhost:8001/
curl http://localhost:8001/health
```

### Part 2: Build with Docker Hardened Image

```bash
# Navigate to DHI directory
cd ../02-dhi-image

# Build using DHI
docker build -f Dockerfile.dhi -t demo-app:dhi .

# Check image size
docker images demo-app:dhi

# Scan for vulnerabilities
docker scout cves demo-app:dhi

# Run the container
docker run -d -p 8002:8000 --name dhi-app demo-app:dhi

# Test the application
curl http://localhost:8002/
curl http://localhost:8002/health
```

### Part 3: Compare Images

```bash
# Direct comparison with Docker Scout
docker scout compare demo-app:dhi --to demo-app:standard --ignore-unchanged

# Or compare DHI with official Python image
docker scout compare dhi.io/python:3.13 --to python:3.13 --platform linux/amd64
```

### Part 4: Verify DHI Security Metadata

```bash
# Inspect SBOM
docker scout sbom dhi.io/python:3.13

# View attestations (requires Docker Scout)
docker scout attestation dhi.io/python:3.13

# Verify signatures with cosign (if installed)
cosign verify dhi.io/python:3.13 \
  --certificate-identity-regexp="https://github.com/docker-hardened-images/*" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

### Part 5: Advanced Multi-Stage Build

```bash
cd ../03-dhi-advanced

# Build advanced DHI image
docker build -f Dockerfile.advanced -t demo-app:advanced .

# Compare all three versions
docker images | grep demo-app
```

### Cleanup

```bash
# Stop and remove containers
docker stop standard-app dhi-app
docker rm standard-app dhi-app

# Remove images (optional)
docker rmi demo-app:standard demo-app:dhi demo-app:advanced
```

## 📊 DHI vs Standard Images Comparison

| Metric | Standard Python Image | Docker Hardened Image | Improvement |
|--------|----------------------|----------------------|-------------|
| **Base Image** | python:3.13 | dhi.io/python:3.13 | Optimized |
| **Image Size** | ~412 MB | ~35 MB | **91% reduction** |
| **Package Count** | ~610 packages | ~80 packages | **87% reduction** |
| **CVE Count** | 1H, 5M, 141L, 2? | 0H, 0M, 0L | **100% reduction** |
| **User** | root (UID 0) | nonroot (UID 65532) | ✅ Secure |
| **Shell Access** | ✅ Available | ❌ Not available | ✅ Secure |
| **Package Manager** | ✅ Available | ❌ Not available | ✅ Secure |
| **SBOM** | ❌ Not available | ✅ Signed | ✅ Transparent |
| **Provenance** | ❌ Limited | ✅ SLSA Level 3 | ✅ Verifiable |
| **Signatures** | ❌ Not signed | ✅ Cryptographically signed | ✅ Trustworthy |
| **VEX** | ❌ No | ✅ Yes | ✅ Exploitability context |
| **Build Tools** | ✅ Included | ❌ Removed | ✅ Secure |
| **License** | Varies | Apache 2.0 | ✅ Open |
| **Maintenance** | Community | Docker Official | ✅ SLA available |

### Real-World Example Output

```
## Overview

                    │    Analyzed Image (DHI)      │    Comparison Image (Standard)
────────────────────┼─────────────────────────────┼────────────────────────────────
  Target            │  dhi.io/python:3.13         │  python:3.13
  vulnerabilities   │  0C  0H  0M  0L             │  0C  1H  5M  141L  2?
                    │       -1  -5  -141  -2      │
  size              │  35 MB (-377 MB)            │  412 MB
  packages          │  80 (-530)                  │  610
```

*Note: Results may vary based on newly discovered CVEs and updates.*

## ✅ Best Practices

### When Using Docker Hardened Images

1. **Always use DHI for production workloads**
   ```dockerfile
   FROM dhi.io/python:3.13
   ```

2. **Pin to specific digests for reproducibility**
   ```dockerfile
   FROM dhi.io/python:3.13@sha256:c215e9da9f84...
   ```

3. **Use multi-stage builds**
   ```dockerfile
   FROM dhi.io/python:3.13-dev AS builder
   # Build stage
   
   FROM dhi.io/python:3.13
   # Runtime stage
   ```

4. **Verify signatures before deployment**
   ```bash
   cosign verify dhi.io/python:3.13
   ```

5. **Scan regularly with Docker Scout**
   ```bash
   docker scout cves dhi.io/python:3.13
   ```

6. **Use Docker Scout policies to enforce DHI usage**
   ```bash
   docker scout policy --org myorg
   ```

7. **Leverage SBOM for compliance**
   ```bash
   docker scout sbom dhi.io/python:3.13 --format spdx
   ```

8. **Run containers read-only when possible**
   ```bash
   docker run --read-only --tmpfs /tmp dhi.io/python:3.13
   ```

9. **Keep DHI images updated**
   - Docker automatically patches and rebuilds
   - Pull latest regularly: `docker pull dhi.io/python:3.13`

10. **Use appropriate variants**
    - Development: `dhi.io/python:3.13-dev`
    - Production: `dhi.io/python:3.13`
    - Alpine: `dhi.io/python:3.13-alpine`
    - Debian: `dhi.io/python:3.13-debian`

### DHI Migration Checklist

- [ ] Identify current base images in use
- [ ] Find equivalent DHI images in catalog
- [ ] Update Dockerfiles to use `dhi.io/*` registry
- [ ] Test applications with DHI images
- [ ] Verify SBOM and provenance
- [ ] Scan with Docker Scout
- [ ] Update CI/CD pipelines
- [ ] Configure Docker Scout policies
- [ ] Deploy to production
- [ ] Monitor and maintain

## 🎓 Learning Path

### For YouTube Video

This demo is structured to cover:

1. **Introduction (5 min)**
   - What are Docker Hardened Images?
   - Why they matter for security

2. **Demo Part 1: Standard vs DHI (10 min)**
   - Build standard image
   - Build DHI image
   - Compare sizes and CVEs
   - Show dramatic improvements

3. **Demo Part 2: Security Features (10 min)**
   - Inspect SBOM
   - Verify signatures
   - Check provenance
   - View VEX statements

4. **Demo Part 3: Real-World Usage (10 min)**
   - Multi-stage builds with DHI
   - Kubernetes deployment
   - CI/CD integration
   - Docker Scout policies

5. **Best Practices & Wrap-up (5 min)**
   - Key takeaways
   - Migration tips
   - Resources for learning more

## 📚 Additional Resources

### Official Docker Documentation
- [Docker Hardened Images (DHI) Home](https://docs.docker.com/dhi/)
- [DHI Features](https://docs.docker.com/dhi/features/)
- [DHI Core Concepts](https://docs.docker.com/dhi/core-concepts/)
- [DHI Quickstart Guide](https://docs.docker.com/dhi/get-started/)
- [DHI How-To Guides](https://docs.docker.com/dhi/how-to/)
- [DHI Migration Guide](https://docs.docker.com/dhi/migration/)

### Docker Hardened Images Catalog
- [Browse DHI Catalog on Docker Hub](https://hub.docker.com/hardened-images/catalog)
- [Start DHI Enterprise Trial](https://hub.docker.com/hardened-images/start-free-trial)

### Security Standards & Frameworks
- [SLSA Framework](https://slsa.dev/)
- [OWASP Container Security](https://owasp.org/www-project-docker-top-10/)
- [CIS Docker Benchmarks](https://www.cisecurity.org/benchmark/docker)
- [NIST Container Security](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf)

### Tools & Scanners
- [Docker Scout](https://docs.docker.com/scout/) - Built-in vulnerability scanning
- [Cosign](https://github.com/sigstore/cosign) - Container signing and verification
- [Trivy](https://trivy.dev/) - Comprehensive vulnerability scanner
- [Grype](https://github.com/anchore/grype) - Vulnerability scanner
- [Syft](https://github.com/anchore/syft) - SBOM generator

### Community & Support
- [Docker Blog - DHI Announcement](http://www.docker.com/blog/docker-hardened-images-for-every-developer/)
- [Docker Community Forums](https://forums.docker.com/)
- [Docker GitHub - DHI Definitions](https://github.com/docker-hardened-images/definitions)
- [Docker Slack Community](https://dockercommunity.slack.com/)

### Related Topics
- [Supply Chain Security](https://docs.docker.com/dhi/core-concepts/sscs/)
- [Software Bill of Materials (SBOM)](https://docs.docker.com/dhi/core-concepts/sbom/)
- [SLSA Provenance](https://docs.docker.com/dhi/core-concepts/slsa/)
- [VEX Statements](https://docs.docker.com/dhi/core-concepts/vex/)
- [Image Signing](https://docs.docker.com/dhi/core-concepts/signatures/)

## 🎥 YouTube Video Outline

### Video Title Ideas
- "Docker Hardened Images: FREE Security for Every Developer"
- "95% Fewer Vulnerabilities with Docker Hardened Images"
- "Secure Your Containers: Docker Hardened Images Explained"
- "From 412MB to 35MB: Docker Hardened Images Demo"

### Target Audience
- DevOps Engineers
- Security Engineers
- Cloud Architects
- Software Developers
- IT Professionals

### Key Points to Cover
1. ✅ Docker Hardened Images are now FREE
2. ✅ 91% smaller images, 95% fewer CVEs
3. ✅ Complete supply chain security (SLSA 3)
4. ✅ Signed SBOMs, provenance, and VEX
5. ✅ Drop-in compatible with existing workflows
6. ✅ Automatic patching by Docker
7. ✅ Live demo showing dramatic improvements
8. ✅ How to migrate existing applications

## 🤝 Contributing

Found improvements or have suggestions? Feel free to:
- Open an issue on GitHub
- Submit a pull request
- Share your DHI migration experience
- Contribute to Docker's DHI definitions repo

## 📝 License

This demo is provided for educational purposes under the MIT License. Docker Hardened Images themselves are licensed under Apache 2.0.

---

## 🔐 Security First, Always!

Remember: **Docker Hardened Images make security the default, not an afterthought.**

- 🎯 Start with DHI from day one
- 🔍 Verify signatures and SBOMs
- 📊 Monitor with Docker Scout
- 🔄 Keep images updated
- 📖 Follow best practices

**Docker Hardened Images: Secure by Default. Free for Everyone. 🚀**

---

**Need Help?**
- 📖 [Read the docs](https://docs.docker.com/dhi/)
- 💬 [Join Docker Community](https://dockercommunity.slack.com/)
- 🎓 [Browse DHI Catalog](https://hub.docker.com/hardened-images/catalog)
- 🚀 [Try DHI Enterprise](https://hub.docker.com/hardened-images/start-free-trial)

---

*Last updated: January 2026*  
*Demo repository for YouTube educational content*
