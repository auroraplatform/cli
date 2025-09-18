#!/usr/bin/env python3
import json
import logging
import os
import time
from kafka import KafkaConsumer, TopicPartition
from clickhouse_driver import Client

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def main():
    # --- Configuration ---
    connection_name = os.getenv('CONNECTION_NAME', 'unknown')
    clickhouse_host = os.getenv('CLICKHOUSE_HOST', 'localhost')
    kafka_broker = os.getenv('KAFKA_BROKER', 'localhost:9092')
    kafka_topic = os.getenv('KAFKA_TOPIC', 'user_events')
    kafka_username = os.getenv('KAFKA_USERNAME', 'admin')
    kafka_password = os.getenv('KAFKA_PASSWORD')
    ca_cert_file = os.getenv('CA_CERT_FILE', '/opt/kafka-consumer/config/ca-cert.pem')
    
    clickhouse_db = os.getenv('CLICKHOUSE_DB', 'default')
    clickhouse_user = os.getenv('CLICKHOUSE_USER', 'default')
    clickhouse_pass = os.getenv('CLICKHOUSE_PASS', '')
    batch_size = int(os.getenv('BATCH_SIZE', '100'))
    batch_timeout = float(os.getenv('BATCH_TIMEOUT', '1.0'))

    if not kafka_password:
        logger.error('KAFKA_PASSWORD environment variable is required')
        return

    logger.info(f'Starting Kafka to ClickHouse ingestion for connection: {connection_name}')
    logger.info(f'Kafka broker: {kafka_broker}, topic: {kafka_topic}')
    logger.info(f'ClickHouse host: {clickhouse_host}, database: {clickhouse_db}')
    logger.info(f'Batch size: {batch_size}, timeout: {batch_timeout}s')

    # --- Connect to ClickHouse ---
    try:
        clickhouse = Client(
            host=clickhouse_host,
            port=9000,
            user=clickhouse_user,
            password=clickhouse_pass,
            database=clickhouse_db
        )
        logger.info('Connected to ClickHouse')
    except Exception as e:
        logger.error(f'Failed to connect to ClickHouse: {e}')
        return

    # --- Connect to Kafka ---
    try:
        consumer = KafkaConsumer(
            bootstrap_servers=[kafka_broker],
            security_protocol='SASL_SSL',
            sasl_mechanism='PLAIN',
            sasl_plain_username=kafka_username,
            sasl_plain_password=kafka_password,
            ssl_check_hostname=False,
            ssl_cafile=ca_cert_file,
            # No group_id for simple consumer - will read all messages
            auto_offset_reset='earliest',
            value_deserializer=lambda x: x.decode('utf-8') if x else "{}",
            consumer_timeout_ms=100 # Poll timeout to check batch timeout
        )
        logger.info('Connected to Kafka')
    except Exception as e:
        logger.error(f'Failed to connect to Kafka: {e}')
        return

    # --- Assign partitions manually ---
    try:
        partitions = consumer.partitions_for_topic(kafka_topic)
        if not partitions:
            logger.error(f'No partitions found for {kafka_topic} topic')
            return
        topic_partitions = [TopicPartition(kafka_topic, p) for p in partitions]
        consumer.assign(topic_partitions)
        logger.info(f'Assigned partitions: {topic_partitions}')
    except Exception as e:
        logger.error(f'Failed to assign partitions: {e}')
        return

    # --- Infer schema from first valid message ---
    schemaArray = []
    try:
        for message in consumer:
            try:
                data = json.loads(message.value)
                logger.info(f"Sample message for schema inference: {data}")
                json_string = json.dumps(data)
                clickhouse.execute("SET schema_inference_make_columns_nullable = 0;")
                clickhouse.execute("SET input_format_null_as_default = 0;")
                escaped_json = json_string.replace("'", "''")
                desc_query = f"DESC format(JSONEachRow, '{escaped_json}');"
                res = clickhouse.execute(desc_query)
                logger.info("Successfully parsed each row")
                for row in res:
                    schema = {
                        'name': row[0],
                        'type': row[1],
                    }
                    schemaArray.append(schema)
                logger.info(f"Schema inferred: {schemaArray}")
                break
            except Exception as e:
                logger.warning(f"Failed to parse message for schema inference: {e}")
                continue
        else:
            logger.error("No valid message found for schema inference.")
            return
    finally:
        consumer.seek_to_beginning()  # Reset offsets to re-consume all messages

    table_name = kafka_topic.replace('.', '_')
    columns = ", ".join([f'{col["name"]} {col["type"]}' for col in schemaArray])
    column_names = ", ".join([col['name'] for col in schemaArray])

    # --- Create ClickHouse database and destination table ---
    create_destination_table = f"""
    CREATE TABLE IF NOT EXISTS {clickhouse_db}.{table_name} (
        {columns}
    ) ENGINE = MergeTree
    ORDER BY (timestamp)
    """
    try:
        clickhouse.execute(create_destination_table)
        logger.info(f"Destination table {clickhouse_db}.{table_name} created/verified.")
    except Exception as e:
        logger.error(f"Failed to create ClickHouse table: {e}")
        return

    def insert_batch(batch, reason=""):
        if batch:
            insert_sql = f"INSERT INTO {clickhouse_db}.{table_name} ({column_names}) VALUES"
            clickhouse.execute(insert_sql, batch)
            logger.info(f'Inserted batch of {len(batch)} messages {reason}.')
            return True
        return False

    # --- Main consumption loop: batch insert ---
    logger.info('Starting main message consumption loop...')
    batch = []
    message_count = 0
    batch_start_time = None

    try:
        while True:
            try:
                message_batch = consumer.poll(timeout_ms=100)

                for topic_partition, messages in message_batch.items():
                    for message in messages:
                        try:
                            try:
                                data = json.loads(message.value)
                            except Exception as e:
                                logger.warning(f'Failed to process message at offset {getattr(message, "offset", "?")}: {e} | Raw value: {message.value}')
                                continue
                        
                            row = [data.get(col['name']) for col in schemaArray]
                            batch.append(row)
                            message_count += 1

                            if len(batch) == 1:
                                batch_start_time = time.time()
                            
                            if len(batch) >= batch_size:
                                if insert_batch(batch, "(size threshold reached)"):
                                    batch = []
                                    batch_start_time = None

                            log_interval = max(10, batch_size // 2) # Logging frequency proportional to batch size
                            if message_count % log_interval == 0:
                                logger.info(f'Processed {message_count} messages so far...')
                    
                        except Exception as e:
                            logger.error(f'Failed to process message at offset {getattr(message, "offset", "?")}: {e} | Raw value: {message.value}')
                            continue
                    
                if batch and batch_start_time and (time.time() - batch_start_time) >= batch_timeout:
                    if insert_batch(batch, "(timeout reached)"):
                        batch = []
                        batch_start_time = None
                
            except KeyboardInterrupt:
                logger.info('Received interrupt signal, shutting down...')
                break
            except Exception as e:
                logger.error(f'Error in consumer loop: {e}')
                continue
        
        # Insert any remaining messages before shutdown
        insert_batch(batch, "(final batch)")
    
    finally:
        consumer.close()
        clickhouse.disconnect()
        logger.info(f'Consumer stopped. Total messages processed: {message_count}')

if __name__ == '__main__':
    main()
