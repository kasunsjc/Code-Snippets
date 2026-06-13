# ── Build stage ───────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir --target /build/deps -r requirements.txt

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM python:3.12-slim

# Non-root user for security
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /build/deps /usr/local/lib/python3.12/site-packages/

COPY app.py .

USER appuser

# Environment variable defaults (overridden at runtime)
ENV CONSUMER_GROUP='$Default' \
    STARTING_POSITION=@latest \
    CHECKPOINT_CONTAINER_NAME=eventhub-checkpoints \
    LOG_LEVEL=INFO

CMD ["python", "-u", "app.py"]
