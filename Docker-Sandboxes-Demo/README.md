# Docker Sandboxes Demo

> **Experimental Feature** - Requires Docker Desktop 4.50 or later

Docker Sandboxes is a new experimental feature that allows you to run AI agents like Claude Code securely in isolated containerized environments. This demo showcases how to use Docker Sandboxes for safe AI agent execution.

## 🎯 What is Docker Sandboxes?

Docker Sandboxes isolates AI coding agents from your local machine while preserving a familiar development experience. Agents can:
- Execute commands safely inside a container
- Install packages without affecting your host
- Modify files in a containerized workspace
- Access Docker (if enabled) for testing containerized apps

**Key Benefits:**
- 🔒 **Security**: Agents run isolated from your host system
- 🔄 **Persistence**: One sandbox per workspace, state maintained across sessions
- 📁 **Workspace Mounting**: Your directory is mounted at the same path in the container
- 🔑 **Git Integration**: Your Git config is automatically injected

## 📋 Prerequisites

- **Docker Desktop 4.50** or later
- **Claude Code subscription** (or other supported AI agents)
- Basic understanding of Docker and AI coding agents

## 🚀 Quick Start

### 1. Check Your Docker Version

```bash
docker version
```

Ensure you have Docker Desktop 4.50 or later.

### 2. Navigate to Your Project

```bash
cd Docker-Sandboxes-Demo
```

### 3. Run Claude in a Sandbox

```bash
docker sandbox run claude
```

On first run, you'll be prompted to authenticate. Credentials are stored in a persistent Docker volume.

### 4. Work with Claude

Once inside the sandbox, Claude has full autonomy to:
- Run commands
- Install packages
- Create and modify files
- Execute your development workflow

## 🛠️ Essential Commands

### List All Sandboxes

```bash
docker sandbox ls
```

Shows all active sandboxes with IDs, names, status, and creation time.

### Inspect a Sandbox

```bash
docker sandbox inspect <sandbox-id>
```

View detailed configuration in JSON format.

### Remove a Sandbox

```bash
docker sandbox rm <sandbox-id>
```

### Remove All Sandboxes

```bash
docker sandbox rm $(docker sandbox ls -q)
```

## 🔧 Advanced Configurations

### 1. Environment Variables

Pass environment variables to the sandbox:

```bash
docker sandbox run \
  -e NODE_ENV=development \
  -e DATABASE_URL=postgresql://localhost/myapp_dev \
  -e DEBUG=true \
  claude
```

### 2. Volume Mounting

Mount additional directories beyond your workspace:

```bash
# Read-only mount
docker sandbox run -v ~/datasets:/data:ro claude

# Multiple mounts
docker sandbox run \
  -v ~/datasets:/data:ro \
  -v ~/models:/models \
  -v ~/.cache/pip:/root/.cache/pip \
  claude
```

### 3. Docker Socket Access

⚠️ **Use with caution** - Grants the agent access to Docker on your host:

```bash
docker sandbox run --mount-docker-socket claude
```

This allows Claude to:
- Build Docker images
- Run containers
- Use Docker Compose
- Test containerized applications

### 4. Custom Templates

Create a custom sandbox template with pre-installed tools:

**Dockerfile:**
```dockerfile
# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:claude-code

RUN <<EOF
# Install uv package manager
curl -LsSf https://astral.sh/uv/install.sh | sh
. ~/.local/bin/env

# Install development tools
uv tool install ruff@latest
uv tool install black@latest
uv tool install pytest@latest
EOF

ENV PATH="$PATH:~/.local/bin"
```

**Build and use:**
```bash
docker build -t my-dev-sandbox .
docker sandbox run --template my-dev-sandbox claude
```

## 📁 Demo Examples

This repository includes several examples:

### 1. **Basic Python Project**
- Simple Flask API
- Claude can set up environment, install dependencies, run tests
- Example: `cd examples/python-api && docker sandbox run claude`

### 2. **Docker-in-Docker**
- Containerized application with Dockerfile
- Claude can build and test Docker images
- Example: `cd examples/docker-app && docker sandbox run --mount-docker-socket claude`

### 3. **Machine Learning Workflow**
- Data processing with volume-mounted datasets
- Model training and storage
- Example: `cd examples/ml-workflow && docker sandbox run -v ~/datasets:/data:ro claude`

## 🔄 Sandbox Lifecycle

### How It Works

1. **First Run**: Docker creates a container from a template image
2. **Workspace Mount**: Your current directory is mounted at the same path
3. **Git Integration**: Your Git credentials are automatically injected
4. **Persistence**: The same sandbox is reused for subsequent runs in this workspace
5. **State Maintained**: Installed packages and files persist across sessions

### When to Recreate

Sandboxes remember their initial configuration. Recreate to change:
- Environment variables (`-e` flag)
- Volume mounts (`-v` flag)
- Docker socket access (`--mount-docker-socket`)
- Credentials mode (`--credentials`)

```bash
# Remove and recreate
docker sandbox rm <sandbox-id>
docker sandbox run [new-options] claude
```

## 🔒 Security Considerations

### What's Safe

✅ Running untrusted code in isolated containers
✅ Testing AI-generated code safely
✅ Experimenting with new tools/packages
✅ Using test/development API keys

### What's Risky

⚠️ Mounting the Docker socket (grants root-level access)
⚠️ Using production API keys or credentials
⚠️ Mounting sensitive host directories
⚠️ Granting network access to production systems

### Best Practices

1. **Use separate sandboxes for different projects**
2. **Never use production credentials in sandboxes**
3. **Be cautious with `--mount-docker-socket`**
4. **Regularly clean up unused sandboxes**
5. **Review agent actions before executing in production**

## 📊 Comparison: Traditional vs Sandbox

| Feature | Traditional Setup | Docker Sandbox |
|---------|------------------|----------------|
| Isolation | ❌ Agent runs on host | ✅ Agent runs in container |
| System Impact | ⚠️ Can modify host | ✅ Changes isolated |
| Package Installation | ⚠️ Affects host environment | ✅ Contained to sandbox |
| Security | ⚠️ Direct host access | ✅ Isolated execution |
| Cleanup | 😰 Manual uninstall | 😊 `docker sandbox rm` |
| Persistence | ✅ Native | ✅ Per-workspace container |

## 🐛 Troubleshooting

### Sandbox Won't Start

```bash
# Check Docker Desktop version
docker version

# Check running sandboxes
docker sandbox ls

# View detailed logs
docker sandbox inspect <sandbox-id>
```

### Container Path Issues

Remember: Your workspace is mounted at the **same absolute path** in the container. If you see path errors, check that you're using absolute paths consistently.

### Agent Not Found

If you get "binary was not found", ensure you're using an official sandbox template:

```bash
docker sandbox run --template docker/sandbox-templates:claude-code claude
```

### Cleanup Issues

Remove all sandboxes and start fresh:

```bash
docker sandbox rm $(docker sandbox ls -q)
docker system prune -a
```

## 📚 Use Cases

### 1. AI-Assisted Development
- Let Claude set up new projects safely
- Test AI-generated code in isolation
- Experiment with new frameworks without host contamination

### 2. Code Review & Testing
- Test pull requests in isolated environments
- Verify containerized applications
- Run integration tests safely

### 3. Learning & Experimentation
- Try new languages and tools
- Test dangerous or experimental code
- Learn Docker in a safe environment

### 4. CI/CD Integration
- Automated testing in consistent environments
- Build validation before deployment
- Security scanning of AI-generated code

## 🔗 Resources

- [Docker Sandboxes Documentation](https://docs.docker.com/ai/sandboxes/)
- [Getting Started Guide](https://docs.docker.com/ai/sandboxes/get-started/)
- [Advanced Configuration](https://docs.docker.com/ai/sandboxes/advanced-config/)
- [CLI Reference](https://docs.docker.com/reference/cli/docker/sandbox/)
- [Troubleshooting](https://docs.docker.com/ai/sandboxes/troubleshooting/)

## 📝 Example Workflows

See [EXAMPLES.md](EXAMPLES.md) for detailed workflow examples including:
- Setting up a Python web application
- Building and testing Docker images
- Machine learning model training
- Multi-service application development

## 🤝 Contributing

This is a demo repository. Feel free to:
- Add your own examples
- Share interesting sandbox configurations
- Report issues or improvements
- Submit pull requests with new use cases

## ⚠️ Release Status

**Docker Sandboxes is an experimental feature.** Features and setup may change. Report issues:
- [Docker Desktop for Mac](https://github.com/docker/for-mac)
- [Docker Desktop for Windows](https://github.com/docker/for-win)
- [Docker Desktop for Linux](https://github.com/docker/desktop-linux)

## 📄 License

MIT License - See LICENSE file for details

---

**Happy Safe Coding! 🚀🔒**
