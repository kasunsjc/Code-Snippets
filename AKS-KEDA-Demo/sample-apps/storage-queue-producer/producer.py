#!/usr/bin/env python3
"""
Azure Storage Queue Producer

Generates sample messages for testing Scenario 01 (Storage Queue + KEDA).
Messages are sent at configurable intervals to simulate load.
"""

import json
import logging
import os
import time
from datetime import datetime, timezone

from azure.storage.queue import QueueClient
from azure.core.exceptions import ResourceExistsError


# ─────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────
def get_config():
    """Load configuration from environment variables."""
    return {
        "connection_string": os.getenv(
            "AZURE_STORAGE_CONNECTION_STRING",
            "UseDevelopmentStorage=true",
        ),
        "queue_name": os.getenv("QUEUE_NAME", "keda-demo-queue"),
        "message_interval": float(os.getenv("MESSAGE_INTERVAL_SECONDS", "2")),
        "batch_size": int(os.getenv("BATCH_SIZE", "1")),
        "log_level": os.getenv("LOG_LEVEL", "INFO"),
    }


# ─────────────────────────────────────────────────────
# Setup logging
# ─────────────────────────────────────────────────────
def setup_logging(log_level):
    """Configure logging for the producer."""
    logging.basicConfig(
        level=getattr(logging, log_level),
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    return logging.getLogger(__name__)


# ─────────────────────────────────────────────────────
# Producer
# ─────────────────────────────────────────────────────
class StorageQueueProducer:
    """Produces messages to Azure Storage Queue."""

    def __init__(self, config, logger):
        self.config = config
        self.logger = logger
        self.message_count = 0
        
        # Connect to queue
        try:
            self.client = QueueClient.from_connection_string(
                conn_str=config["connection_string"],
                queue_name=config["queue_name"],
            )
            # Ensure queue exists (ignore if already exists)
            try:
                self.client.create_queue()
            except ResourceExistsError:
                # Queue already exists, that's fine
                pass
            self.logger.info(
                f"Connected to queue '{config['queue_name']}' "
                f"in storage account"
            )
        except Exception as e:
            self.logger.error(f"Failed to connect to queue: {e}")
            raise

    def produce_message(self, batch_num, msg_num):
        """Create and send a sample message."""
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "batch": batch_num,
            "message": msg_num,
            "data": f"Sample workload message {self.message_count}",
        }
        
        try:
            self.client.send_message(json.dumps(payload))
            self.message_count += 1
            self.logger.info(
                f"Sent message {self.message_count}: "
                f"batch={payload['batch']}, msg={payload['message']}"
            )
        except Exception as e:
            self.logger.error(f"Failed to send message: {e}")

    def run(self):
        """Main producer loop."""
        batch_num = 0
        
        self.logger.info(
            f"Producer started. Interval: {self.config['message_interval']}s, "
            f"Batch size: {self.config['batch_size']}"
        )
        
        try:
            while True:
                batch_num += 1
                
                # Send batch of messages
                for msg_num in range(1, self.config["batch_size"] + 1):
                    self.produce_message(batch_num, msg_num)
                
                # Wait before next batch
                time.sleep(self.config["message_interval"])
        except KeyboardInterrupt:
            self.logger.info(
                f"Producer stopped. Total messages sent: {self.message_count}"
            )


def main():
    """Entry point."""
    config = get_config()
    logger = setup_logging(config["log_level"])
    
    try:
        producer = StorageQueueProducer(config, logger)
        producer.run()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        exit(1)


if __name__ == "__main__":
    main()
