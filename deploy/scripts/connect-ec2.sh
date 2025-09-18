#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cross-platform base64 encode (no line wrapping)
base64_noline() {
    if base64 --help 2>&1 | grep -q -- "-w"; then
        # Linux - supports -w flag and direct file reading
        base64 -w 0 "$1"
    else
        # macOS - doesn't support -w flag, need to read file first
        cat "$1" | base64 | tr -d '\n'
    fi
}

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to execute SSM command and wait for completion
execute_ssm_command() {
    local instance_id="$1"
    local commands="$2"
    local description="$3"
    
    print_status "Executing SSM command: $description"
    
    # Send the command
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters "{\"commands\":[\"$commands\"]}" \
        --output text \
        --query 'Command.CommandId')
    
    if [ $? -ne 0 ]; then
        print_error "Failed to send SSM command"
        return 1
    fi
    
    print_status "Command sent with ID: $command_id"
    
    # Wait for command completion
    local status=""
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        status=$(aws ssm list-command-invocations \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --output text \
            --query 'CommandInvocations[0].Status')
        
        if [ "$status" = "Success" ]; then
            print_success "SSM command completed successfully"
            return 0
        elif [ "$status" = "Failed" ] || [ "$status" = "Cancelled" ]; then
            print_error "SSM command failed with status: $status"

            # Show error details if there's actual error content
            error_content=$(aws ssm list-command-invocations \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --output text \
                --query 'CommandInvocations[0].StandardErrorContent')

            if [ "$error_content" != "None" ] && [ -n "$error_content" ]; then
                print_error "Error details: $error_content"
            else
                print_status "No error details available. Command completed with non-zero exit code"
            fi
            return 1
        fi
        
        print_status "Waiting for command completion... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_error "SSM command timed out"
    return 1
}

# Function to upload file content via SSM
upload_file_via_ssm() {
    local instance_id="$1"
    local file_path="$2"
    local remote_path="$3"
    local description="$4"
    
    print_status "Uploading file via SSM: $description"
    
    # Read file content and escape for JSON
    local file_content=$(base64_noline "$file_path")
    
    local commands="echo '$file_content' | base64 -d > '$remote_path'"
    
    execute_ssm_command "$instance_id" "$commands" "$description"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 -n <connection_name> -k <kafka_broker> -t <topic> -u <username> -p <password> -c <ca_cert_file>"
    echo ""
    echo "Required parameters:"
    echo "  -n    Connection name (unique identifier for this connection)"
    echo "  -k    Kafka broker address (e.g., your-kafka-broker:9093)"
    echo "  -t    Kafka topic name"
    echo "  -u    Kafka username"
    echo "  -p    Kafka password"
    echo "  -c    Path to CA certificate file"
    echo "  -f    Filename of the CA certificate (e.g., my-root-ca.crt)"
    echo ""
    echo "Example:"
    echo "  $0 -n 'user-events-connection' -k 'your-kafka-broker:9093' -t 'user_events' -u 'your-username' -p 'your-password' -c './ca-cert.pem' -f 'ca-cert.pem'"
    exit 1
}

# Parse command line arguments
while getopts "n:k:t:u:p:c:f:h" opt; do
    case $opt in
        n) CONNECTION_NAME="$OPTARG" ;;
        k) KAFKA_BROKER="$OPTARG" ;;
        t) KAFKA_TOPIC="$OPTARG" ;;
        u) KAFKA_USERNAME="$OPTARG" ;;
        p) KAFKA_PASSWORD="$OPTARG" ;;
        c) CA_CERT_FILE="$OPTARG" ;;
        f) CA_CERT_FILENAME="$OPTARG" ;;
        h) show_usage ;;
        *) show_usage ;;
    esac
done

# Validate required parameters
if [ -z "$CONNECTION_NAME" ] || [ -z "$KAFKA_BROKER" ] || [ -z "$KAFKA_TOPIC" ] || [ -z "$KAFKA_USERNAME" ] || [ -z "$KAFKA_PASSWORD" ] || [ -z "$CA_CERT_FILE" ] || [ -z "$CA_CERT_FILENAME" ]; then
    print_error "Missing required parameters"
    show_usage
fi

# Validate CA certificate file exists
if [ ! -f "$CA_CERT_FILE" ]; then
    print_error "CA certificate file not found: $CA_CERT_FILE"
    exit 1
fi

print_status "Starting Kafka-to-ClickHouse connection setup..."
print_status "Connection Name: $CONNECTION_NAME"
print_status "Kafka Broker: $KAFKA_BROKER"
print_status "Kafka Topic: $KAFKA_TOPIC"

# Step 1: Get infrastructure details from Terraform
print_status "Step 1: Getting infrastructure details..."

TERRAFORM_DIR="${TERRAFORM_DIR:-/opt/terraform}"
INFRA_ENV="$TERRAFORM_DIR/infra.env"

# Check if infra.env exists and source it
if [ -f "$INFRA_ENV" ]; then
    print_status "Loading infrastructure details from $INFRA_ENV"
    # shellcheck disable=SC1090
    . "$INFRA_ENV"
else
    print_error "infra.env not found at $INFRA_ENV"
    print_error "Please ensure the deployment script created this file with infrastructure details"
    exit 1
fi

# Validate that we have the required values
if [ -z "$KAFKA_CONSUMER_INSTANCE_ID" ] || [ -z "$CLICKHOUSE_PRIVATE_IP" ]; then
    print_error "Missing required infrastructure details in infra.env"
    print_error "KAFKA_CONSUMER_INSTANCE_ID: $KAFKA_CONSUMER_INSTANCE_ID"
    print_error "CLICKHOUSE_PRIVATE_IP: $CLICKHOUSE_PRIVATE_IP"
    exit 1
fi

print_success "Kafka Consumer Instance ID: $KAFKA_CONSUMER_INSTANCE_ID"
print_success "ClickHouse Private IP: $CLICKHOUSE_PRIVATE_IP"

# Step 2: Check if connection already exists
print_status "Step 2: Checking if connection already exists..."
check_service_commands="sudo systemctl list-unit-files | grep -q kafka-consumer-$CONNECTION_NAME"
if execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$check_service_commands" "Check if service exists"; then
    print_error "Connection '$CONNECTION_NAME' already exists. Use 'disconnect.sh' to remove it first."
    exit 1
else
    print_success "Connection '$CONNECTION_NAME' does not exist, proceeding with setup..."
fi

# Step 3: Upload CA certificate
print_status "Step 3: Uploading CA certificate..."
upload_file_via_ssm "$KAFKA_CONSUMER_INSTANCE_ID" "$CA_CERT_FILE" "/tmp/$CA_CERT_FILENAME" "Upload CA certificate"
print_success "CA certificate uploaded"

# Step 4: Create connection-specific Python script
print_status "Step 4: Creating connection-specific Python script..."

# Changed: Use script directory instead of assuming current directory
SCRIPT_DIR="$(dirname "$0")"
PYTHON_SCRIPT_PATH="$SCRIPT_DIR/kafka_to_clickhouse.py"

# Check if Python script exists
if [ ! -f "$PYTHON_SCRIPT_PATH" ]; then
    print_error "Python script not found: $PYTHON_SCRIPT_PATH"
    exit 1
fi

cp "$PYTHON_SCRIPT_PATH" "/tmp/kafka_to_clickhouse_$CONNECTION_NAME.py"

# Upload the Python script
upload_file_via_ssm "$KAFKA_CONSUMER_INSTANCE_ID" "/tmp/kafka_to_clickhouse_$CONNECTION_NAME.py" "/tmp/kafka_to_clickhouse_$CONNECTION_NAME.py" "Upload Python script"
print_success "Python script uploaded"

# Step 5: Configure service on Kafka Consumer instance
print_status "Step 5: Configuring connection on Kafka Consumer instance..."
cat > "/tmp/setup_$CONNECTION_NAME.sh" << EOF
#!/bin/bash
sudo mkdir -p /opt/kafka-consumer/connections/$CONNECTION_NAME &&
sudo mv /tmp/$CA_CERT_FILENAME /opt/kafka-consumer/connections/$CONNECTION_NAME/$CA_CERT_FILENAME &&
sudo mv /tmp/kafka_to_clickhouse_$CONNECTION_NAME.py /opt/kafka-consumer/connections/$CONNECTION_NAME/kafka_to_clickhouse.py &&
echo "$KAFKA_TOPIC" | sudo tee /opt/kafka-consumer/connections/$CONNECTION_NAME/kafka_topic.txt > /dev/null &&
sudo chown -R kafka-consumer:kafka-consumer /opt/kafka-consumer/connections/$CONNECTION_NAME &&
sudo chmod 644 /opt/kafka-consumer/connections/$CONNECTION_NAME/$CA_CERT_FILENAME &&
sudo chmod +x /opt/kafka-consumer/connections/$CONNECTION_NAME/kafka_to_clickhouse.py &&
sudo chmod 644 /opt/kafka-consumer/connections/$CONNECTION_NAME/kafka_topic.txt
EOF

upload_file_via_ssm "$KAFKA_CONSUMER_INSTANCE_ID" "/tmp/setup_$CONNECTION_NAME.sh" "/tmp/setup_$CONNECTION_NAME.sh" "Upload setup script"
setup_commands="chmod +x /tmp/setup_$CONNECTION_NAME.sh && /tmp/setup_$CONNECTION_NAME.sh"
execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$setup_commands" "Setup connection directory and files"
rm -f "/tmp/setup_$CONNECTION_NAME.sh"

# Create systemd service file
service_content="[Unit]
Description=Kafka to ClickHouse Consumer - $CONNECTION_NAME
After=network.target

[Service]
Type=simple
User=kafka-consumer
Group=kafka-consumer
WorkingDirectory=/opt/kafka-consumer/connections/$CONNECTION_NAME
ExecStart=/usr/bin/python3 /opt/kafka-consumer/connections/$CONNECTION_NAME/kafka_to_clickhouse.py
Environment=CONNECTION_NAME=$CONNECTION_NAME
Environment=CLICKHOUSE_HOST=$CLICKHOUSE_PRIVATE_IP
Environment=KAFKA_BROKER=$KAFKA_BROKER
Environment=KAFKA_TOPIC=$KAFKA_TOPIC
Environment=KAFKA_USERNAME=$KAFKA_USERNAME
Environment=KAFKA_PASSWORD=$KAFKA_PASSWORD
Environment=CA_CERT_FILE=/opt/kafka-consumer/connections/$CONNECTION_NAME/$CA_CERT_FILENAME
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/kafka-consumer/connections/$CONNECTION_NAME /var/log/kafka-consumer /var/lib/kafka-consumer

[Install]
WantedBy=multi-user.target"

# Write service file content to a temporary file
echo "$service_content" > "/tmp/kafka-consumer-$CONNECTION_NAME.service"

# Upload service file
upload_file_via_ssm "$KAFKA_CONSUMER_INSTANCE_ID" "/tmp/kafka-consumer-$CONNECTION_NAME.service" "/tmp/kafka-consumer-$CONNECTION_NAME.service" "Upload systemd service file"

# Install and start service
start_service_script="
sudo mv /tmp/kafka-consumer-$CONNECTION_NAME.service /etc/systemd/system/kafka-consumer-$CONNECTION_NAME.service &&
sudo systemctl daemon-reload &&
sudo systemctl enable kafka-consumer-$CONNECTION_NAME &&
sudo systemctl start kafka-consumer-$CONNECTION_NAME &&
sleep 5 &&
if sudo systemctl is-active --quiet kafka-consumer-$CONNECTION_NAME; then
    echo 'Service started successfully'
else
    echo 'Service failed to start'
    sudo systemctl status kafka-consumer-$CONNECTION_NAME --no-pager
    exit 1
fi
"

echo "$start_service_script" > "/tmp/start_service_$CONNECTION_NAME.sh"
upload_file_via_ssm "$KAFKA_CONSUMER_INSTANCE_ID" "/tmp/start_service_$CONNECTION_NAME.sh" "/tmp/start_service_$CONNECTION_NAME.sh" "Upload start service script"
start_service_commands="chmod +x /tmp/start_service_$CONNECTION_NAME.sh && /tmp/start_service_$CONNECTION_NAME.sh"
execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$start_service_commands" "Install and start systemd service"
rm -f "/tmp/start_service_$CONNECTION_NAME.sh"

# Step 6: Test the connection
print_status "Step 6: Testing the connection..."

# Test Kafka connection
cat > "/tmp/kafka_test_$CONNECTION_NAME.py" << EOF
import os
from kafka import KafkaConsumer
try:
    consumer = KafkaConsumer(
        bootstrap_servers=['$KAFKA_BROKER'],
        security_protocol='SASL_SSL',
        sasl_mechanism='PLAIN',
        sasl_plain_username='$KAFKA_USERNAME',
        sasl_plain_password='$KAFKA_PASSWORD',
        ssl_check_hostname=False,
        ssl_cafile='/opt/kafka-consumer/connections/$CONNECTION_NAME/$CA_CERT_FILENAME'
    )
    print('Kafka connection test successful')
    consumer.close()
except Exception as e:
    print(f'Kafka connection test failed: {e}')
    exit(1)
EOF

upload_file_via_ssm "$KAFKA_CONSUMER_INSTANCE_ID" "/tmp/kafka_test_$CONNECTION_NAME.py" "/tmp/kafka_test_$CONNECTION_NAME.py" "Upload Kafka test script"
kafka_test_commands="python3 /tmp/kafka_test_$CONNECTION_NAME.py"
execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$kafka_test_commands" "Test Kafka connection"
rm -f "/tmp/kafka_test_$CONNECTION_NAME.py"

# Test ClickHouse connection
cat > "/tmp/clickhouse_test_$CONNECTION_NAME.py" << EOF
from clickhouse_driver import Client
try:
    clickhouse = Client(host='$CLICKHOUSE_PRIVATE_IP', port=9000, user='default', password='', database='default')
    print('ClickHouse connection test successful')
    clickhouse.disconnect()
except Exception as e:
    print(f'ClickHouse connection test failed: {e}')
    exit(1)
EOF

upload_file_via_ssm "$KAFKA_CONSUMER_INSTANCE_ID" "/tmp/clickhouse_test_$CONNECTION_NAME.py" "/tmp/clickhouse_test_$CONNECTION_NAME.py" "Upload ClickHouse test script"
clickhouse_test_commands="python3 /tmp/clickhouse_test_$CONNECTION_NAME.py"
execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$clickhouse_test_commands" "Test ClickHouse connection"
rm -f "/tmp/clickhouse_test_$CONNECTION_NAME.py"

# Clean up temporary files
rm -f "/tmp/kafka_to_clickhouse_$CONNECTION_NAME.py" "/tmp/kafka-consumer-$CONNECTION_NAME.service" "/tmp/clickhouse_test_$CONNECTION_NAME.py"

print_success "Connection '$CONNECTION_NAME' setup completed!"
print_status "Connection Summary:"
print_status "  - Connection Name: $CONNECTION_NAME"
print_status "  - Kafka Broker: $KAFKA_BROKER"
print_status "  - Kafka Topic: $KAFKA_TOPIC"
print_status "  - ClickHouse Table: user_events_$CONNECTION_NAME"
print_status "  - Service: kafka-consumer-$CONNECTION_NAME"
print_status ""
print_status "Next steps:"
print_status "  1. Monitor the connection: aws ssm start-session --target $KAFKA_CONSUMER_INSTANCE_ID"
print_status "  2. Check logs: sudo journalctl -u kafka-consumer-$CONNECTION_NAME -f"
print_status "  3. Verify data: clickhouse-client --host $CLICKHOUSE_PRIVATE_IP --query \"SELECT count() FROM user_events_$CONNECTION_NAME\""
print_status "  4. Disconnect: ./disconnect.sh -n $CONNECTION_NAME"
