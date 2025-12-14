# Docker Sandboxes Examples

Practical examples demonstrating Docker Sandboxes capabilities.

## Example 1: Python Web Application

### Scenario
You want Claude to set up and run a Flask API safely.

### Commands

```bash
cd examples/python-api
docker sandbox run claude
```

### What Claude Can Do

```
You: "Set up a Flask API with user authentication"

Claude: *creates virtual environment, installs dependencies*
  python -m venv venv
  source venv/bin/activate
  pip install flask flask-jwt-extended
  *creates app.py with auth endpoints*
  flask run
```

### Benefits
- Dependencies installed only in the sandbox
- No pollution of host Python environment
- Easy cleanup with `docker sandbox rm`

---

## Example 2: Docker-in-Docker Development

### Scenario
Testing a containerized application with Claude's help.

### Commands

```bash
cd examples/docker-app
docker sandbox run --mount-docker-socket claude
```

### What Claude Can Do

```
You: "Build the Docker image and run the tests"

Claude: *builds and tests the application*
  docker build -t myapp:test .
  docker run myapp:test npm test
  docker run -d -p 3000:3000 myapp:test
  curl http://localhost:3000/health
```

### ⚠️ Security Note
The `--mount-docker-socket` flag grants full Docker access. Use only for trusted code.

---

## Example 3: Machine Learning Workflow

### Scenario
Training ML models with mounted datasets.

### Commands

```bash
docker sandbox run \
  -v ~/datasets:/data:ro \
  -v ~/models:/models \
  -v ~/.cache/pip:/root/.cache/pip \
  claude
```

### What Claude Can Do

```
You: "Train a model on the MNIST dataset and save it"

Claude: *accesses mounted data and trains model*
  pip install tensorflow numpy
  python train.py --data /data/mnist --output /models/mnist_model.h5
  python evaluate.py --model /models/mnist_model.h5
```

### Benefits
- Read-only dataset mount prevents accidental modifications
- Trained models persisted to host
- Pip cache shared across sandbox recreations

---

## Example 4: Multi-Service Development

### Scenario
Developing a full-stack application with database.

### Commands

```bash
cd examples/fullstack-app
docker sandbox run \
  -e DATABASE_URL=postgresql://localhost/myapp_dev \
  -e REDIS_URL=redis://localhost:6379 \
  -e NODE_ENV=development \
  --mount-docker-socket \
  claude
```

### What Claude Can Do

```
You: "Start the application stack with docker-compose"

Claude: *uses docker-compose for multi-container setup*
  docker-compose up -d
  docker-compose logs -f web
  npm run migrate
  npm run seed
```

---

## Example 5: Custom Development Environment

### Scenario
Create a reusable sandbox with your preferred tools.

### Custom Template Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:claude-code

# Install Python tools
RUN <<EOF
curl -LsSf https://astral.sh/uv/install.sh | sh
. ~/.local/bin/env
uv tool install ruff@latest
uv tool install black@latest
uv tool install mypy@latest
uv tool install pytest@latest
EOF

# Install Node.js tools
RUN <<EOF
npm install -g pnpm typescript ts-node
pnpm config set store-dir ~/.pnpm-store
EOF

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="$PATH:~/.local/bin:~/.cargo/bin"
```

### Build and Use

```bash
docker build -t my-polyglot-sandbox .
docker sandbox run --template my-polyglot-sandbox claude
```

### What You Get
- Pre-installed Python, Node.js, and Rust toolchains
- Linters and formatters ready to use
- Faster sandbox startup
- Consistent development environment

---

## Example 6: Testing Infrastructure Code

### Scenario
Testing Terraform/Infrastructure code safely.

### Commands

```bash
cd examples/terraform-project
docker sandbox run \
  -v ~/.aws:/root/.aws:ro \
  -v ~/.azure:/root/.azure:ro \
  -e TF_VAR_environment=dev \
  claude
```

### What Claude Can Do

```
You: "Validate the Terraform configuration and plan"

Claude: *tests infrastructure code*
  terraform init
  terraform validate
  terraform plan
  tflint
  checkov -d .
```

### Benefits
- AWS/Azure credentials read-only mounted
- No risk of accidental infrastructure changes
- Testing in isolated environment

---

## Example 7: Security Scanning

### Scenario
Scan a project for vulnerabilities before deployment.

### Commands

```bash
cd examples/nodejs-app
docker sandbox run \
  -v ~/.npm:/root/.npm \
  --mount-docker-socket \
  claude
```

### What Claude Can Do

```
You: "Run security scans on this project"

Claude: *performs comprehensive security analysis*
  npm audit
  npm audit fix --dry-run
  docker build -t app:scan .
  docker scout cves app:scan
  trivy image app:scan
```

---

## Example 8: Documentation Generation

### Scenario
Generate and build documentation safely.

### Commands

```bash
cd examples/docs-project
docker sandbox run claude
```

### What Claude Can Do

```
You: "Generate API documentation and build the docs site"

Claude: *creates and builds documentation*
  pip install sphinx sphinx-rtd-theme
  sphinx-quickstart docs
  sphinx-apidoc -o docs/api src/
  sphinx-build docs/ docs/_build
  python -m http.server 8000 --directory docs/_build
```

---

## Example 9: Database Migrations

### Scenario
Testing database migrations in isolation.

### Commands

```bash
docker sandbox run \
  -e DATABASE_URL=postgresql://postgres:password@localhost:5432/testdb \
  --mount-docker-socket \
  claude
```

### What Claude Can Do

```
You: "Start a PostgreSQL container and run migrations"

Claude: *sets up database and migrates*
  docker run -d --name testdb \
    -e POSTGRES_PASSWORD=password \
    -p 5432:5432 postgres:15
  npm run migrate
  npm run seed:test
  npm test
```

---

## Example 10: Code Refactoring

### Scenario
Large-scale refactoring with AI assistance.

### Commands

```bash
cd examples/legacy-app
docker sandbox run claude
```

### What Claude Can Do

```
You: "Refactor this codebase to use TypeScript and modern React patterns"

Claude: *safely refactors in isolated environment*
  npm install --save-dev typescript @types/react @types/node
  *creates tsconfig.json*
  *converts .js files to .tsx*
  *updates imports and types*
  npm run build
  npm test
```

### Benefits
- Test major refactoring without risk
- Easy rollback if needed
- Verify builds and tests pass before committing

---

## Tips for Effective Sandbox Usage

### 1. Be Specific with Prompts
```
❌ "Set up the project"
✅ "Install dependencies, configure the database, and start the dev server"
```

### 2. Use Environment Variables
```bash
docker sandbox run \
  -e API_KEY=${DEV_API_KEY} \
  -e LOG_LEVEL=debug \
  claude
```

### 3. Mount Caches for Speed
```bash
docker sandbox run \
  -v ~/.cache/pip:/root/.cache/pip \
  -v ~/.npm:/root/.npm \
  -v ~/.cargo:/root/.cargo \
  claude
```

### 4. Create Project-Specific Templates
Build custom templates for different project types (Python, Node, Go, etc.)

### 5. Use Descriptive Sandbox Names
The sandbox name is based on your workspace path, so organize projects clearly.

---

## Common Patterns

### Pattern: Fresh Start for Each Task

```bash
# Remove existing sandbox
docker sandbox rm $(docker sandbox ls -q --filter "name=my-project")

# Start fresh with new configuration
docker sandbox run -e NEW_VAR=value claude
```

### Pattern: Persistent Development Environment

```bash
# First run - installs everything
docker sandbox run claude

# Subsequent runs - reuses container
cd ~/project && docker sandbox run claude
```

### Pattern: Testing Multiple Configurations

```bash
# Test with Python 3.11
docker sandbox run --template python:3.11 claude

# Remove and test with Python 3.12
docker sandbox rm <id>
docker sandbox run --template python:3.12 claude
```

---

## Debugging Tips

### View Sandbox Logs

```bash
docker logs $(docker sandbox ls -q | head -1)
```

### Execute Commands Directly

```bash
docker exec -it <sandbox-id> bash
```

### Inspect Sandbox Configuration

```bash
docker sandbox inspect <sandbox-id> | jq '.Config.Env'
```

### Check Mounted Volumes

```bash
docker sandbox inspect <sandbox-id> | jq '.Mounts'
```

---

## Next Steps

- Explore the [advanced configuration guide](https://docs.docker.com/ai/sandboxes/advanced-config/)
- Check out [Claude Code documentation](https://docs.docker.com/ai/sandboxes/claude-code/)
- Join the Docker community to share your sandbox configurations
- Contribute your own examples to this repository!
