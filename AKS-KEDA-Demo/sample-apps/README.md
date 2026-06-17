# Sample Apps — Producers & Consumers

This folder contains producer and consumer applications for testing KEDA scaling scenarios locally before deploying to AKS.

## Overview

### Scenario 01: Storage Queue (Batch Processing)
- **Producer**: `storage-queue-producer/` — generates messages at configurable intervals
- **Consumer**: `storage-queue-consumer/` — processes messages from the queue
- **Scaling**: KEDA scales based on queue depth

### Scenario 05: Event Hub (Streaming)
- **Producer**: `eventhub-producer/` — generates events at configurable intervals  
- **Consumer**: `eventhub-consumer/` — processes events from Event Hub partitions
- **Scaling**: KEDA scales based on per-consumer-group lag

## Quick Start

### 1. Configure Environment Variables

```bash
# Copy the template
cp .env.example .env

# Fill in Azure connection strings from deployment outputs:
# Retrieve Storage Account connection string:
az storage account show-connection-string \
  --name <storage-account-name> \
  --resource-group rg-aks-keda-demo \
  --query connectionString -o tsv

# Retrieve Event Hub namespace connection string:
az eventhubs namespace authorization-rule keys list \
  --resource-group rg-aks-keda-demo \
  --namespace-name <namespace> \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv
```

### 2. Start All Services

```bash
# Build and start producers + consumers
docker compose up --build

# Or in detached mode
docker compose up -d --build
```

### 3. Observe Logs

```bash
# Follow all logs
docker compose logs -f

# Follow specific service
docker compose logs -f storage-queue-producer
docker compose logs -f eventhub-producer
```

### 4. Adjust Load

Edit `.env` to change producer behavior:

| Variable | Purpose | Example |
|----------|---------|---------|
| `MESSAGE_INTERVAL_SECONDS` | Delay between message batches | `2` (send batch every 2 seconds) |
| `EVENT_INTERVAL_SECONDS` | Delay between event batches | `1` (high frequency) |
| `BATCH_SIZE` | Messages/events per batch | `10` (heavy load burst) |
| `LOG_LEVEL` | Logging verbosity | `DEBUG`, `INFO`, `WARNING` |

**Example: Simulate high load**
```env
MESSAGE_INTERVAL_SECONDS=0.5
EVENT_INTERVAL_SECONDS=0.5
BATCH_SIZE=50
```

### 5. Stop Services

```bash
# Stop all containers
docker compose down

# Remove volumes (optional)
docker compose down -v
```

## Testing Checklist

- [ ] Producer sends messages/events consistently (check logs)
- [ ] Consumer receives and processes messages/events
- [ ] No authentication errors in logs
- [ ] Lag/queue depth metric shows up in Azure portal
- [ ] Ready to test KEDA scaling in AKS

## Troubleshooting

### Producer Can't Connect

**Error**: `BrokenPipeError`, `NameError`, or connection refused

**Fix**:
```bash
# Verify credentials in .env are correct
cat .env | grep CONNECTION_STRING

# Test connectivity manually
az storage account show --name <account> --resource-group rg-aks-keda-demo
az eventhubs namespace show --name <namespace> --resource-group rg-aks-keda-demo
```

### No Messages/Events in Storage or Event Hub

**Error**: Empty queue or partition

**Fix**:
```bash
# Check if producer is running
docker compose ps

# Check producer logs
docker compose logs storage-queue-producer
docker compose logs eventhub-producer

# Verify BATCH_SIZE > 0
grep BATCH_SIZE .env
```

### Consumer Stops Processing

**Error**: Consumer container exits

**Fix**:
```bash
# Check consumer logs for errors
docker compose logs eventhub-consumer

# Restart the service
docker compose restart eventhub-consumer
```

## Local vs. AKS

These apps work identically on both platforms:

| Aspect | Local | AKS |
|--------|-------|-----|
| Connection String | From `.env` | From Kubernetes secret |
| Checkpoint Store | Disabled (local demo) | Enabled for KEDA lag tracking |
| Log Output | Docker logs | `kubectl logs <pod>` |
| Scaling | Manual (docker compose) | Automatic (KEDA) |

## Next Steps

Once local testing is successful:

1. Build and push images to ACR:
   ```bash
   docker build -t <acr>.azurecr.io/storage-queue-consumer:v1 storage-queue-consumer/
   docker build -t <acr>.azurecr.io/eventhub-consumer:v1 eventhub-consumer/
   docker push <acr>.azurecr.io/storage-queue-consumer:v1
   docker push <acr>.azurecr.io/eventhub-consumer:v1
   ```

2. Deploy consumers to AKS (see scenario YAML files in `../scenarios/`)

3. KEDA will automatically scale consumer pods based on queue/lag metrics
