#!/usr/bin/env python3
"""
Azure Event Hub Producer

Generates sample events for testing Scenario 05 (Event Hub + KEDA).
Events are sent at configurable intervals to simulate load.
"""

import json
import logging
import os
import time
from datetime import datetime, timezone

from azure.eventhub import EventHubProducerClient, EventData


# ─────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────
def get_config():
    """Load configuration from environment variables."""
    return {
        "connection_string": os.getenv("AZURE_EVENTHUB_CONNECTION_STRING", ""),
        "eventhub_name": os.getenv("EVENTHUB_NAME", "keda-demo-hub"),
        "event_interval": float(os.getenv("EVENT_INTERVAL_SECONDS", "2")),
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
class EventHubProducer:
    """Produces events to Azure Event Hub."""

    def __init__(self, config, logger):
        self.config = config
        self.logger = logger
        self.event_count = 0
        
        # Create producer client
        try:
            self.client = EventHubProducerClient.from_connection_string(
                conn_str=config["connection_string"],
                eventhub_name=config["eventhub_name"],
            )
            self.logger.info(
                f"Connected to Event Hub '{config['eventhub_name']}'"
            )
        except Exception as e:
            self.logger.error(f"Failed to connect to Event Hub: {e}")
            raise

    def produce_event(self, batch_num, event_num):
        """Create and send a sample event."""
        payload = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "batch": batch_num,
            "event": event_num,
            "data": f"Sample workload event {self.event_count}",
        }
        
        try:
            event_data = EventData(json.dumps(payload))
            self.client.send_event(event_data)
            self.event_count += 1
            self.logger.info(
                f"Sent event {self.event_count}: "
                f"batch={payload['batch']}, event={payload['event']}"
            )
        except Exception as e:
            self.logger.error(f"Failed to send event: {e}")

    def run(self):
        """Main producer loop."""
        batch_num = 0
        
        self.logger.info(
            f"Producer started. Interval: {self.config['event_interval']}s, "
            f"Batch size: {self.config['batch_size']}"
        )
        
        try:
            while True:
                batch_num += 1
                
                # Send batch of events
                for event_num in range(1, self.config["batch_size"] + 1):
                    self.produce_event(batch_num, event_num)
                
                # Wait before next batch
                time.sleep(self.config["event_interval"])
        except KeyboardInterrupt:
            self.logger.info(
                f"Producer stopped. Total events sent: {self.event_count}"
            )
        finally:
            self.client.close()


def main():
    """Entry point."""
    config = get_config()
    logger = setup_logging(config["log_level"])
    
    if not config["connection_string"]:
        logger.error(
            "AZURE_EVENTHUB_CONNECTION_STRING not set. "
            "Cannot connect to Event Hub."
        )
        exit(1)
    
    try:
        producer = EventHubProducer(config, logger)
        producer.run()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        exit(1)


if __name__ == "__main__":
    main()
