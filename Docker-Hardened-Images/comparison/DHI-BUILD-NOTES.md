# DHI Build Fix - Important Notes

## Issue: DHI Production Images Don't Include pip

Docker Hardened Images production variants are intentionally minimal and **don't include pip** for security reasons. This is a feature, not a bug!

## Solutions

### Solution 1: Use Multi-Stage Build (Recommended)

The `Dockerfile.dhi` now uses a multi-stage build:
- **Stage 1**: Uses `dhi.io/python:3.13-dev` (includes pip)
- **Stage 2**: Uses `dhi.io/python:3.13` (minimal runtime)

This gives you the best of both worlds:
- ✅ pip available for installing dependencies
- ✅ Minimal final image without pip (more secure)

### Solution 2: Use Only Dev Variant (Simpler but larger)

If you want a simpler single-stage build:

```dockerfile
FROM dhi.io/python:3.13-dev

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

EXPOSE 8000
CMD ["python", "app.py"]
```

**Trade-off**: Slightly larger image (~10MB more) but includes pip

### Solution 3: Pre-built Dependencies (Advanced)

Build a custom image with your dependencies, then use that as base.

## Understanding DHI Variants

| Variant | Purpose | Includes pip? | Size | Best For |
|---------|---------|---------------|------|----------|
| `dhi.io/python:3.13` | Production | ❌ No | ~35 MB | Running apps |
| `dhi.io/python:3.13-dev` | Development | ✅ Yes | ~45 MB | Building apps |
| `dhi.io/python:3.13-alpine` | Minimal (musl) | ❌ No | ~25 MB | Production |
| `dhi.io/python:3.13-alpine-dev` | Dev (musl) | ✅ Yes | ~35 MB | Building |

## Why This Design?

DHI production images exclude pip because:
1. **Security**: pip is not needed at runtime and increases attack surface
2. **Size**: Removing pip and build tools saves ~10MB
3. **Immutability**: Can't install packages at runtime = more predictable
4. **Best Practice**: Separates build-time from runtime dependencies

This follows the **principle of least privilege** and is a security best practice.

## Quick Test

```bash
# This works (multi-stage build)
cd 02-dhi-image
docker build -f Dockerfile.dhi -t demo-app:dhi .

# Or use the advanced example (already multi-stage)
cd 03-dhi-advanced
docker build -f Dockerfile.advanced -t demo-app:advanced .
```

## For Your YouTube Video

**Make this a feature, not a problem!**

Explain:
1. DHI production images are intentionally minimal
2. No pip = more secure, smaller images
3. Multi-stage builds solve this elegantly
4. This is a security best practice, not a limitation

This is actually a **great demonstration** of how DHI prioritizes security!
