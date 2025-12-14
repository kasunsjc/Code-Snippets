# Docker-in-Docker Example

Demonstrates building and testing Docker images using Docker Sandboxes with socket access.

## Run with Docker Sandbox

```bash
cd examples/docker-app
docker sandbox run --mount-docker-socket claude
```

⚠️ **Security Note**: The `--mount-docker-socket` flag grants full Docker access.

## Example Prompts for Claude

1. **"Build the Docker image and run it"**
   ```
   docker build -t sandbox-app:test .
   docker run -d -p 3000:3000 --name test-app sandbox-app:test
   ```

2. **"Run the test suite inside a container"**
   ```
   docker run --rm sandbox-app:test npm test
   ```

3. **"Check the health endpoint"**
   ```
   curl http://localhost:3000/health
   ```

4. **"Build multi-architecture images"**
   ```
   docker buildx build --platform linux/amd64,linux/arm64 -t sandbox-app:multi .
   ```

## What Claude Can Do

With Docker socket access, Claude can:
- ✅ Build Docker images
- ✅ Run and manage containers
- ✅ Use Docker Compose
- ✅ Inspect images and containers
- ✅ Test containerized applications
- ✅ Push to registries (with credentials)

## Safety Tips

1. Only use with trusted code
2. Don't mount production credentials
3. Remove sandbox after testing
4. Review Dockerfile before building
