# Docker Offload Troubleshooting Guide

## Common Error: "failed to build: request returned 500 Internal Server Error"

If you see this error:
```
ERROR: failed to build: request returned 500 Internal Server Error for API route and version http://%2FUsers%2F...%2F.docker%2Fcloud%2Fdocker-cloud.sock/_ping
```

### Possible Causes & Solutions

### 1. Docker Offload Not Properly Started

**Check Status:**
```bash
docker offload status
```

**Solution:**
```bash
# Stop any existing offload session
docker offload stop

# Wait a moment
sleep 2

# Start fresh
docker offload start

# Verify it started
docker offload status
```

### 2. Docker Desktop Not Signed In

**Solution:**
1. Open Docker Desktop
2. Click "Sign in" in the top right
3. Sign in with your Docker account
4. Wait for sync to complete
5. Try `docker offload start` again

### 3. No Docker Offload Access

**Check Access:**
1. Open Docker Desktop
2. Look for the offload toggle in the header (☁️ icon)
3. If not visible, you don't have access

**Solution:**
- Contact your organization owner
- They need to subscribe at: https://www.docker.com/products/docker-offload/
- They must add you to the organization with offload access

### 4. Docker Desktop Version Too Old

**Check Version:**
```bash
docker version
```

**Requirements:**
- Docker Desktop 4.50 or later required

**Solution:**
- Update Docker Desktop from https://www.docker.com/products/docker-desktop

### 5. Builder Context Issues

The error might be related to Docker buildx context.

**Reset Builder:**
```bash
# List builders
docker buildx ls

# If you see docker-cloud builder with errors, remove it
docker buildx rm docker-cloud 2>/dev/null || true

# Use default builder
docker buildx use default

# Try building again
docker offload start
docker build -t docker-offload-demo:latest .
```

### 6. Corrupted Offload Configuration

**Reset Configuration:**
```bash
# Stop offload
docker offload stop

# Remove any cached state
rm -rf ~/.docker/cloud/ 2>/dev/null || true

# Restart Docker Desktop
# (Use Docker Desktop menu: Quit Docker Desktop, then start again)

# Try again
docker offload start
```

## Working Without Docker Offload

If you can't get Docker Offload working, you can still run this demo locally:

### Option 1: Build and Run Locally

```bash
# Simply build without offload
docker build -t docker-offload-demo:latest .

# Run locally
docker run -d -p 8080:8080 --name offload-demo docker-offload-demo:latest

# Access the app
open http://localhost:8080
```

### Option 2: Use the Demo Script

The updated demo script now handles offload failures gracefully:

```bash
./demo.sh
# When asked if you have offload access, answer "N"
# The demo will run locally instead
```

## Verification Steps

Before trying the demo, verify each requirement:

### 1. Docker Desktop Running
```bash
docker ps
# Should show running containers or empty list (not an error)
```

### 2. Docker Version
```bash
docker version
# Client version should be 4.50 or higher for offload
```

### 3. Signed In
```bash
docker info | grep Username
# Should show your Docker username
```

### 4. Offload Available
```bash
# This command should exist (even if offload isn't accessible)
docker offload --help
```

### 5. Offload Access
- Open Docker Desktop
- Look for toggle/icon in header
- Go to Settings > Features > Docker Offload
- Should be visible and enabled

## Alternative: Test Locally First

To verify the demo app works before trying offload:

```bash
# Build locally
docker build -t docker-offload-demo:latest .

# Run locally
docker run -d -p 8080:8080 --name test docker-offload-demo:latest

# Test
curl http://localhost:8080/health

# If this works, the issue is definitely with offload setup
docker stop test && docker rm test
```

## Getting Help

If none of these solutions work:

1. **Check Docker Status Page**
   - https://www.dockerstatus.com/
   - Look for any service incidents

2. **Docker Community Forums**
   - https://forums.docker.com/
   - Search for similar issues

3. **Contact Your Organization Admin**
   - Verify offload subscription is active
   - Confirm you're added to the organization
   - Check if there are usage limits

4. **Docker Support**
   - If your organization has a support plan
   - Provide the full error message and docker version

## Error Log Collection

If you need to report the issue, collect these details:

```bash
# Docker version
docker version > docker-info.txt

# Docker info
docker info >> docker-info.txt

# Offload status
docker offload status >> docker-info.txt 2>&1

# Builder info
docker buildx ls >> docker-info.txt

# System info
uname -a >> docker-info.txt

# Show the file
cat docker-info.txt
```

## Success Indicators

When Docker Offload is working properly, you should see:

1. **In Terminal:**
   ```
   $ docker offload start
   ✓ Docker Offload started
   
   $ docker offload status
   Status: Active
   Session: Running
   ```

2. **In Docker Desktop:**
   - Cloud icon (☁️) in header
   - Purple-tinted UI
   - Hourglass icon (⏳) in footer showing session time

3. **During Build:**
   ```
   $ docker build -t test .
   [+] Building X.Xs (in cloud)
   ```
   - Should indicate "in cloud" or show cloud builder

4. **When Running:**
   ```
   $ docker ps
   CONTAINER ID   IMAGE   ...
   ```
   - Containers run normally
   - Port forwarding works
   - Logs accessible

## Final Notes

- Docker Offload is in **Early Access** - some issues are expected
- Not all organizations have offload enabled yet
- This demo works perfectly without offload (just runs locally instead)
- The demo.sh script now handles failures gracefully

## Quick Recovery

If completely stuck:

```bash
# Nuclear option - reset everything
docker offload stop
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker buildx use default

# Start fresh
docker build -t docker-offload-demo:latest .
docker run -d -p 8080:8080 docker-offload-demo:latest

# Test
curl http://localhost:8080/health
```

This will at least get the demo running locally!
