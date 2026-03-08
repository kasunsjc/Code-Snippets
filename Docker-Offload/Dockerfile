# Multi-stage Dockerfile optimized for Docker Offload
# This demonstrates efficient cloud builds with layer caching

# Stage 1: Build dependencies
FROM python:3.11-slim as builder

LABEL maintainer="demo@example.com"
LABEL description="Docker Offload Demo Application"

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
# Separate layer for better caching in cloud builds
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime image
FROM python:3.11-slim

WORKDIR /app

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy Python packages from builder
COPY --from=builder /root/.local /usr/local

# Copy application code
COPY app.py .

# Environment variables
ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV DEPLOYMENT_TYPE="Docker Offload"
ARG BUILD_DATE
ENV BUILD_DATE=${BUILD_DATE}
ENV VERSION=1.0.0

# Expose application port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "2", "--timeout", "60", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
