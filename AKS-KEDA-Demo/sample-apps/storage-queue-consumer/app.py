"""
Azure Storage Queue Consumer
─────────────────────────────
Continuously dequeues and processes messages from an Azure Storage Queue.
Designed to work alongside KEDA's azure-queue scaler (Scenario 01).

When KEDA detects messages accumulating in the queue it scales out this
Deployment; when the queue drains it scales back in — all the way to zero.

Environment variables:
  AZURE_STORAGE_CONNECTION_STRING  (required) Storage account connection string
  QUEUE_NAME                       (default: keda-demo-queue)
  POLL_INTERVAL_SECONDS            (default: 5)
  MAX_MESSAGES_PER_POLL            (default: 32)  max supported by the SDK is 32
  VISIBILITY_TIMEOUT_SECONDS       (default: 30)  hide msg from other consumers
  LOG_LEVEL                        (default: INFO)
"""

import os
import time
import signal
import logging

from azure.storage.queue import QueueClient
from azure.core.exceptions import AzureError, ResourceNotFoundError

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)-8s [%(name)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
logger = logging.getLogger("storage-queue-consumer")

# ── Configuration ─────────────────────────────────────────────────────────────
CONNECTION_STRING = os.environ["AZURE_STORAGE_CONNECTION_STRING"]
QUEUE_NAME = os.environ.get("QUEUE_NAME", "keda-demo-queue")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL_SECONDS", "5"))
MAX_MESSAGES = min(int(os.environ.get("MAX_MESSAGES_PER_POLL", "32")), 32)
VISIBILITY_TIMEOUT = int(os.environ.get("VISIBILITY_TIMEOUT_SECONDS", "30"))

# ── Graceful shutdown ─────────────────────────────────────────────────────────
_running = True


def _shutdown(signum, _frame: object) -> None:
    global _running
    logger.info("Shutdown signal received — draining current batch then stopping.")
    _running = False


signal.signal(signal.SIGTERM, _shutdown)
signal.signal(signal.SIGINT, _shutdown)


# ── Business logic ────────────────────────────────────────────────────────────
def process_message(content: str, msg_id: str) -> None:
    """
    Replace the body of this function with your real processing logic.
    The message is only deleted from the queue after this returns without
    raising an exception, ensuring at-least-once delivery.
    """
    logger.info(f"  [id={msg_id[:8]}…] {content}")
    # Simulate work (remove / replace in a real app)
    time.sleep(0.05)


# ── Main loop ─────────────────────────────────────────────────────────────────
def main() -> None:
    logger.info("=== Storage Queue Consumer starting ===")
    logger.info(f"  Queue          : {QUEUE_NAME}")
    logger.info(f"  Poll interval  : {POLL_INTERVAL}s")
    logger.info(f"  Max per poll   : {MAX_MESSAGES}")
    logger.info(f"  Visibility TTL : {VISIBILITY_TIMEOUT}s")

    client = QueueClient.from_connection_string(CONNECTION_STRING, QUEUE_NAME)

    processed_total = 0
    error_streak = 0

    while _running:
        try:
            messages = list(
                client.receive_messages(
                    max_messages=MAX_MESSAGES,
                    visibility_timeout=VISIBILITY_TIMEOUT,
                )
            )
            error_streak = 0

            if messages:
                for msg in messages:
                    try:
                        process_message(msg.content, msg.id)
                        client.delete_message(msg.id, msg.pop_receipt)
                        processed_total += 1
                    except Exception as exc:  # noqa: BLE001
                        # Leave message in queue so another consumer can retry
                        logger.error(f"Failed to process message {msg.id}: {exc}")
                logger.info(
                    f"Batch complete — {len(messages)} processed "
                    f"(total: {processed_total})"
                )
            else:
                logger.debug(f"Queue empty — next poll in {POLL_INTERVAL}s")

        except ResourceNotFoundError:
            logger.error(
                f"Queue '{QUEUE_NAME}' not found. "
                "Check QUEUE_NAME and that the queue exists in the storage account."
            )
            error_streak += 1
        except AzureError as exc:
            logger.error(f"Azure error: {exc}")
            error_streak += 1
        except Exception as exc:  # noqa: BLE001
            logger.exception(f"Unexpected error: {exc}")
            error_streak += 1

        # Back-off if there are repeated errors (cap at 60s)
        sleep_time = POLL_INTERVAL if error_streak == 0 else min(POLL_INTERVAL * (2 ** error_streak), 60)
        if _running:
            time.sleep(sleep_time)

    logger.info(f"Consumer stopped. Total messages processed: {processed_total}")


if __name__ == "__main__":
    main()
