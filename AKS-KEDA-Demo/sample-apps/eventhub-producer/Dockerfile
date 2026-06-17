# =======================================================
# Multi-stage build for eventhub-producer
# =======================================================
FROM python:3.12-slim AS builder

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# ─────────────────────────────────────────────────────
# Runtime stage
# ─────────────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

# Copy Python dependencies from builder
COPY --from=builder /root/.local /root/.local

# Copy application code
COPY producer.py .

# Set PATH to use user-installed packages
ENV PATH=/root/.local/bin:$PATH \
    PYTHONUNBUFFERED=1

ENTRYPOINT ["python", "producer.py"]
