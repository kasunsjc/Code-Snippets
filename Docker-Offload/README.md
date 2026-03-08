# Docker Offload Demo

> **Demonstrating Docker's new cloud execution feature for building and running containers**

This demo showcases **Docker Offload**, a fully managed service that lets you build and run containers in the cloud while using your local Docker Desktop tools and familiar workflow.

## 🌟 What is Docker Offload?

Docker Offload extends your local Docker development workflow into scalable, cloud-powered infrastructure. It enables you to:

- **Build faster** - Use powerful cloud resources instead of local CPU/RAM
- **Run anywhere** - Execute containers in cloud even from VDI or low-powered machines
- **Stay local** - Keep using Docker Desktop, CLI, and Compose - no new tools to learn
- **Work seamlessly** - Port forwarding and bind mounts work exactly as they do locally

## 🎯 Key Benefits

| Benefit | Description |
|---------|-------------|
| ⚡ **Speed** | Cloud builds are faster with dedicated resources |
| 💻 **VDI-Friendly** | Works on virtual desktops & systems without nested virtualization |
| 🔄 **Seamless** | Use same Docker commands - just toggle offload on/off |
| 💰 **Cost-Effective** | Pay only when building or running (auto-idles after 5 min) |
| 🔒 **Secure** | Encrypted tunnels between Desktop and cloud |
| 🛠️ **Hybrid** | Switch between local and cloud execution anytime |

## 📋 Prerequisites

Before using this demo, ensure you have:

1. **Docker Desktop 4.50 or later**
   - Download from [docker.com](https://www.docker.com/products/docker-desktop)
   
2. **Docker Offload Access**
   - Your organization must subscribe to Docker Offload
   - Organization owner sign up: [docker.com/products/docker-offload](https://www.docker.com/products/docker-offload/)
   - You must be added to the organization
   
3. **Signed in to Docker Desktop**
   - Open Docker Desktop
   - Sign in with your Docker account
   - Verify the offload toggle appears in the header

## 🚀 Quick Start

### Option 1: Automated Demo (Recommended)

Run the interactive demo script:

```bash
./demo.sh
```

This will guide you through:
1. ✅ Checking prerequisites
2. 🏗️ Building with Docker Offload
3. 🚀 Running containers in the cloud
4. 🧪 Testing the application
5. 📊 Monitoring resources

### Option 2: Manual Workflow

#### 1. Start Docker Offload

```bash
# Enable cloud execution
docker offload start

# Check status
docker offload status
```

You'll see a cloud icon (☁️) in Docker Desktop header when active.

#### 2. Build the Application

```bash
# Build in the cloud - uses cloud resources!
docker build -t docker-offload-demo:latest .

# Or with build args
docker build -t docker-offload-demo:latest \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) .
```

The build happens in Docker's cloud infrastructure, not on your local machine!

#### 3. Run the Container

```bash
# Run container in the cloud
docker run -d -p 8080:8080 --name offload-demo docker-offload-demo:latest

# Check it's running
docker ps
```

#### 4. Access the Application

Open your browser to [http://localhost:8080](http://localhost:8080)

Or test via curl:

```bash
# Health check
curl http://localhost:8080/health

# System information
curl http://localhost:8080/api/info | jq

# Run compute task
curl -X POST http://localhost:8080/api/process \
  -H 'Content-Type: application/json' \
  -d '{"iterations": 5000000}' | jq
```

#### 5. Run with Docker Compose

```bash
# Start multi-container stack in cloud
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down
```

## 📁 Project Structure

```
Docker-Offload/
├── app.py                 # Flask web application with demo endpoints
├── requirements.txt       # Python dependencies
├── Dockerfile            # Multi-stage optimized for cloud builds
├── docker-compose.yml    # Multi-service configuration
├── .dockerignore         # Build optimization
├── demo.sh              # Interactive demo script
├── commands.sh          # Command reference
└── README.md            # This file
```

## 🎨 Demo Application Features

The Flask application demonstrates various use cases:

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Web UI with system information dashboard |
| `/health` | GET | Health check for monitoring |
| `/api/info` | GET | Detailed JSON system information |
| `/api/process` | POST | CPU-intensive computation demo |
| `/api/build-info` | GET | Docker build metadata |

### Example Requests

```bash
# Get system information
curl http://localhost:8080/api/info

# Process compute task
curl -X POST http://localhost:8080/api/process \
  -H 'Content-Type: application/json' \
  -d '{"iterations": 1000000}'

# Get build info
curl http://localhost:8080/api/build-info
```

## 🔄 Switching Between Local and Cloud

One of Docker Offload's key features is seamless toggling:

```bash
# Build locally
docker offload stop
docker build -t demo:local .

# Build in cloud
docker offload start  
docker build -t demo:cloud .

# Compare the build times!
```

The same applies to `docker run`, `docker compose`, and all Docker commands!

## 📊 Monitoring Usage

### In Docker Desktop

1. **Session Duration** - Check footer for hourglass icon (⏳)
2. **Insights** - Navigate to **Offload > Insights** for detailed metrics
3. **Cloud Icon** - Purple UI with cloud icon when offload is active

### Via CLI

```bash
# Check current status
docker offload status

# View container stats
docker stats offload-demo

# Check logs
docker logs -f offload-demo
```

## ⚙️ Configuration

### Idle Timeout

Docker Offload automatically idles after ~5 minutes of inactivity to save costs.

To configure:
1. Open **Docker Desktop Settings**
2. Navigate to **Features > Docker Offload**
3. Adjust **Idle Timeout** (default: 5 minutes)

### Multiple Organizations

If you're part of multiple organizations with offload access:

```bash
docker offload start
# You'll be prompted to select which organization to use
```

## 🎯 Use Cases

### Perfect For:

✅ **Resource-Intensive Builds**
- Large multi-stage builds
- Compilation of native dependencies
- Building for multiple architectures

✅ **VDI Environments**
- Virtual desktops without nested virtualization
- Remote development environments
- Citrix, VMware Horizon, etc.

✅ **Low-Powered Machines**
- Laptops with limited CPU/RAM
- Older hardware
- Development on the go

✅ **Development & Testing**
- Rapid iteration with fast builds
- Testing on different platforms
- CI/CD pipeline optimization

### Not Ideal For:

❌ **Long-Running Production Workloads**
- Use orchestration platforms like Kubernetes instead
- Offload is for development and testing

❌ **Extremely Large Images**
- Consider image optimization techniques first
- Use multi-stage builds to reduce size

## 🔐 Security Features

- 🔒 **Encrypted tunnels** between Docker Desktop and cloud
- 🔑 **Secure secrets management** for build arguments
- 👤 **Non-root user** in container (see Dockerfile)
- 🛡️ **Minimal base image** (python:3.11-slim)
- 📦 **Multi-stage builds** to reduce attack surface

## 🐛 Troubleshooting

### Offload Won't Start

**Problem**: `docker offload start` fails

**Solutions**:
1. Verify Docker Desktop version (4.50+)
2. Ensure you're signed in to Docker Desktop
3. Check organization has offload subscription
4. Verify you're added to the organization

```bash
# Check version
docker version

# Check offload status
docker offload status
```

### Can't See Offload Toggle

**Problem**: No toggle in Docker Desktop header

**Solutions**:
1. Update Docker Desktop to 4.50+
2. Check if offload is disabled in settings
3. Verify organization subscription
4. Contact your organization admin

### Container Won't Start

**Problem**: Container fails to run

**Solutions**:
```bash
# Check logs
docker logs offload-demo

# Inspect container
docker inspect offload-demo

# Try locally first
docker offload stop
docker run -d -p 8080:8080 --name test docker-offload-demo:latest
```

### Port Already in Use

**Problem**: Port 8080 is already allocated

**Solution**:
```bash
# Use different port
docker run -d -p 8081:8080 --name offload-demo docker-offload-demo:latest

# Or stop conflicting container
docker ps
docker stop <container-name>
```

## 💰 Pricing & Billing

Docker Offload uses usage-based pricing:

- **Committed Usage** - Pre-purchase hours for discounted rates
- **On-Demand Usage** - Pay-as-you-go per session
- **Idle State** - No charges when idle (auto-idles after 5 min)

Organization owners can:
- Monitor usage in Docker Hub
- Set up billing preferences
- View detailed session history

For pricing details: [docs.docker.com/offload/usage](https://docs.docker.com/offload/usage/)

## 📚 Additional Resources

### Documentation
- [Docker Offload Docs](https://docs.docker.com/offload/)
- [Quickstart Guide](https://docs.docker.com/offload/quickstart/)
- [Configuration](https://docs.docker.com/offload/configuration/)
- [Usage & Billing](https://docs.docker.com/offload/usage/)

### Getting Started
- [Sign Up](https://www.docker.com/products/docker-offload/)
- [Docker Desktop Download](https://www.docker.com/products/docker-desktop)

### Support
- [Docker Community Forums](https://forums.docker.com/)
- [Give Feedback](https://docs.docker.com/offload/feedback/)

## 🧹 Cleanup

### Stop the Demo

```bash
# Stop and remove container
docker stop offload-demo
docker rm offload-demo

# Or with compose
docker compose down

# Remove image
docker rmi docker-offload-demo:latest
```

### Stop Docker Offload

```bash
# Stop offload (return to local execution)
docker offload stop

# Note: Offload auto-stops after ~5 minutes of idle time
```

## 🎬 Demo Script for Presentations

Perfect workflow for live demos:

```bash
# 1. Show status
docker offload status

# 2. Start offload
docker offload start

# 3. Build (show it's fast!)
time docker build -t demo .

# 4. Run
docker run -d -p 8080:8080 --name demo docker-offload-demo:latest

# 5. Open browser
open http://localhost:8080

# 6. Show it's running in cloud
curl http://localhost:8080/api/info | jq '.application'

# 7. Cleanup
docker stop demo && docker rm demo
docker offload stop
```

## 🤝 Contributing

This is a demo project. Feel free to:
- Fork and modify for your use cases
- Submit issues for bugs or improvements
- Share your Docker Offload experiences

## 📄 License

This demo is provided as-is for educational purposes.

## 🙋 FAQ

**Q: Do I need to change my Dockerfile?**  
A: No! Your existing Dockerfiles work as-is with offload.

**Q: Does Docker Compose work with offload?**  
A: Yes! All Docker Compose commands work seamlessly.

**Q: Can I use bind mounts?**  
A: Yes! Bind mounts work transparently with offload.

**Q: What happens to my data when offload stops?**  
A: Running containers and images are removed when offload idles or stops. Use volumes for persistence.

**Q: Can I use offload in CI/CD pipelines?**  
A: Yes, but consider [Docker Build Cloud](https://docs.docker.com/build-cloud/) for CI/CD specific features.

**Q: Is this the same as Docker Build Cloud?**  
A: No. Build Cloud is specifically for building. Offload handles both builds AND running containers.

---

**Happy Offloading! 🐳☁️**

For questions or issues, please refer to the [troubleshooting section](#-troubleshooting) or [Docker documentation](https://docs.docker.com/offload/).
