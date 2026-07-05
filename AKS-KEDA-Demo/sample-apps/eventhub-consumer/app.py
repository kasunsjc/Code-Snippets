"""
Azure Event Hub Consumer
─────────────────────────
Receives and processes events from an Azure Event Hub using the Event Processor
pattern. Supports optional Azure Blob Storage checkpointing, which is required
when pairing with KEDA's azure-event-hubs scaler (Scenario 05).

Environment variables (required):
  AZURE_EVENTHUB_CONNECTION_STRING   Event Hub namespace connection string
  EVENTHUB_NAME                      Name of the Event Hub

Environment variables (optional):
  CONSUMER_GROUP                     Consumer group (default: $Default)
  STARTING_POSITION                  Where to start reading when no checkpoint
                                     exists. Use "@latest" (default) to read
                                     only new events, or "-1" to read from the
                                     beginning of the retention window.
  AZURE_STORAGE_CHECKPOINT_CONNECTION_STRING
                                     Storage account connection string for the
                                     checkpoint store. Required when using the
                                     KEDA azure-event-hubs scaler so that KEDA
                                     can measure consumer-group lag.
  CHECKPOINT_CONTAINER_NAME          Blob container name for checkpoints.
                                     (default: eventhub-checkpoints)
  LOG_LEVEL                          (default: INFO)
"""

from __future__ import annotations

import os
import signal
import logging

from azure.eventhub import EventHubConsumerClient, PartitionContext
from azure.core.exceptions import AzureError

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)-8s [%(name)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
logger = logging.getLogger("eventhub-consumer")

# ── Configuration ─────────────────────────────────────────────────────────────
CONNECTION_STRING = os.environ["AZURE_EVENTHUB_CONNECTION_STRING"]
EVENTHUB_NAME = os.environ["EVENTHUB_NAME"]
CONSUMER_GROUP = os.environ.get("CONSUMER_GROUP", "$Default")
STARTING_POSITION = os.environ.get("STARTING_POSITION", "@latest")
CHECKPOINT_CS = os.environ.get("AZURE_STORAGE_CHECKPOINT_CONNECTION_STRING", "")
CHECKPOINT_CONTAINER = os.environ.get("CHECKPOINT_CONTAINER_NAME", "eventhub-checkpoints")

# ── Graceful shutdown ─────────────────────────────────────────────────────────
_client: EventHubConsumerClient | None = None


def _shutdown(signum: int, _frame: object) -> None:
    logger.info("Shutdown signal received — closing client.")
    if _client is not None:
        _client.close()


signal.signal(signal.SIGTERM, _shutdown)
signal.signal(signal.SIGINT, _shutdown)


# ── Event callbacks ───────────────────────────────────────────────────────────
def process_event(body: str, partition_id: str, sequence_number: int) -> None:
    """
    Replace the body of this function with your real processing logic.
    update_checkpoint() is called after this returns, so a failure here
    will NOT advance the checkpoint — the event will be re-delivered.
    """
    logger.info(
        f"  [partition={partition_id} seq={sequence_number}] {body}"
    )


def on_event(partition_context: PartitionContext, event) -> None:
    try:
        process_event(
            body=event.body_as_str(encoding="utf-8"),
            partition_id=partition_context.partition_id,
            sequence_number=event.sequence_number,
        )
        # Persist the checkpoint so this offset is not reprocessed on restart
        try:
            partition_context.update_checkpoint(event)
            logger.debug(
                f"Checkpoint updated: partition={partition_context.partition_id} "
                f"seq={event.sequence_number} offset={event.offset}"
            )
        except Exception as cp_exc:  # noqa: BLE001
            logger.error(
                f"Failed to update checkpoint on partition {partition_context.partition_id}: {cp_exc}"
            )
            raise  # Re-raise to ensure event is reprocessed
    except Exception as exc:  # noqa: BLE001
        logger.error(f"Error processing event on partition {partition_context.partition_id}: {exc}")


def on_partition_initialize(partition_context: PartitionContext) -> None:
    logger.info(f"Partition claimed: {partition_context.partition_id}")
    # Write an initial checkpoint to ensure KEDA can start tracking lag immediately.
    # Without this, KEDA may report all events as unprocessed until the first
    # event arrives and is checkpointed.
    try:
        if partition_context.last_enqueued_event_properties:
            logger.info(
                f"Partition {partition_context.partition_id} initial state: "
                f"last_seq={partition_context.last_enqueued_event_properties.get('sequence_number', 'N/A')}"
            )
    except Exception:  # noqa: BLE001, S110
        pass  # last_enqueued_event_properties may not be available


def on_partition_close(partition_context: PartitionContext, reason) -> None:
    logger.info(f"Partition {partition_context.partition_id} closed — reason: {reason}")


def on_error(partition_context: PartitionContext, error: Exception) -> None:
    pid = getattr(partition_context, "partition_id", "N/A")
    logger.error(f"Error on partition {pid}: {error}")


# ── Client factory ────────────────────────────────────────────────────────────
def _build_client() -> EventHubConsumerClient:
    checkpoint_store = None

    if CHECKPOINT_CS:
        try:
            from azure.eventhub.extensions.checkpointstoreblob import BlobCheckpointStore

            checkpoint_store = BlobCheckpointStore.from_connection_string(
                CHECKPOINT_CS, CHECKPOINT_CONTAINER
            )
            logger.info(
                f"Checkpoint store: Azure Blob Storage "
                f"(container={CHECKPOINT_CONTAINER})"
            )
        except ImportError:
            logger.warning(
                "azure-eventhub-checkpointstoreblob is not installed. "
                "Falling back to in-memory checkpointing. "
                "Add it to requirements.txt to enable persistence."
            )
    else:
        logger.info(
            "Checkpoint store: in-memory only — "
            "set AZURE_STORAGE_CHECKPOINT_CONNECTION_STRING to enable "
            "persistence and KEDA lag tracking."
        )

    return EventHubConsumerClient.from_connection_string(
        CONNECTION_STRING,
        consumer_group=CONSUMER_GROUP,
        eventhub_name=EVENTHUB_NAME,
        checkpoint_store=checkpoint_store,
    )


# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    global _client

    logger.info("=== Event Hub Consumer starting ===")
    logger.info(f"  Event Hub      : {EVENTHUB_NAME}")
    logger.info(f"  Consumer group : {CONSUMER_GROUP}")
    logger.info(f"  Starting pos   : {STARTING_POSITION}")

    _client = _build_client()

    try:
        with _client:
            _client.receive(
                on_event=on_event,
                on_error=on_error,
                on_partition_initialize=on_partition_initialize,
                on_partition_close=on_partition_close,
                starting_position=STARTING_POSITION,
            )
    except AzureError as exc:
        logger.error(f"Azure error: {exc}")
    except Exception as exc:  # noqa: BLE001
        logger.exception(f"Unexpected error: {exc}")
    finally:
        logger.info("Consumer stopped.")


if __name__ == "__main__":
    main()
