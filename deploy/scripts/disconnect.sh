#!/bin/bash

# Kafka-to-ClickHouse Connection Disconnect Manager
# Usage: ./disconnect.sh -n <connection_name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
            # Get error details
            aws ssm list-command-invocations \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --output text \
                --query 'CommandInvocations[0].StandardErrorContent'
            return 1
        fi
        
        print_status "Waiting for command completion... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_error "SSM command timed out"
    return 1
}

# Function to show usage
show_usage() {
    echo "Usage: $0 -n <connection_name>"
    echo ""
    echo "Required parameters:"
    echo "  -n    Connection name to disconnect and remove"
    echo ""
    echo "Example:"
    echo "  $0 -n 'user-events-prod'"
    echo ""
    echo "This will:"
echo "  1. Stop the Kafka consumer service"
echo "  2. Disable the service"
echo "  3. Remove the service file"
echo "  4. Remove the connection directory and files"
echo "  5. Preserve the ClickHouse table (data remains available)"
    exit 1
}

# Parse command line arguments
while getopts "n:h" opt; do
    case $opt in
        n) CONNECTION_NAME="$OPTARG" ;;
        h) show_usage ;;
        *) show_usage ;;
    esac
done

# Validate required parameters
if [ -z "$CONNECTION_NAME" ]; then
    print_error "Missing required parameter: connection name"
    show_usage
fi

print_status "Starting Kafka-to-ClickHouse connection removal..."
print_status "Connection Name: $CONNECTION_NAME"

# Step 1: Get infrastructure details from Terraform
print_status "Step 1: Getting infrastructure details..."
# KAFKA_CONSUMER_INSTANCE_ID=$(cd terraform && terraform output -raw kafka_consumer_instance_id 2>/dev/null || echo "")
# CLICKHOUSE_PRIVATE_IP=$(cd terraform && terraform output -raw clickhouse_private_ip 2>/dev/null || echo "")
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

if [ -z "$KAFKA_CONSUMER_INSTANCE_ID" ] || [ -z "$CLICKHOUSE_PRIVATE_IP" ]; then
    print_error "Missing required infrastructure details in infra.env"
    print_error "KAFKA_CONSUMER_INSTANCE_ID: $KAFKA_CONSUMER_INSTANCE_ID"
    print_error "CLICKHOUSE_PRIVATE_IP: $CLICKHOUSE_PRIVATE_IP"
    exit 1
fi

print_success "Kafka Consumer Instance ID: $KAFKA_CONSUMER_INSTANCE_ID"
print_success "ClickHouse Private IP: $CLICKHOUSE_PRIVATE_IP"

# Step 2: Check if connection exists
print_status "Step 2: Checking if connection exists..."
check_service_commands="sudo systemctl list-unit-files | grep -q kafka-consumer-$CONNECTION_NAME"
if ! execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$check_service_commands" "Check if service exists"; then
    print_error "Connection '$CONNECTION_NAME' does not exist."
    exit 1
fi

print_success "Connection '$CONNECTION_NAME' found"

# Step 3: Stop and remove the service
print_status "Step 3: Stopping and removing the service..."
remove_service_commands="if sudo systemctl is-active --quiet kafka-consumer-$CONNECTION_NAME; then echo 'Stopping service kafka-consumer-$CONNECTION_NAME...'; sudo systemctl stop kafka-consumer-$CONNECTION_NAME; sleep 2; fi; if sudo systemctl is-enabled --quiet kafka-consumer-$CONNECTION_NAME; then echo 'Disabling service kafka-consumer-$CONNECTION_NAME...'; sudo systemctl disable kafka-consumer-$CONNECTION_NAME; fi; if [ -f '/etc/systemd/system/kafka-consumer-$CONNECTION_NAME.service' ]; then echo 'Removing service file...'; sudo rm /etc/systemd/system/kafka-consumer-$CONNECTION_NAME.service; fi; sudo systemctl daemon-reload; if [ -d '/opt/kafka-consumer/connections/$CONNECTION_NAME' ]; then echo 'Removing connection directory...'; sudo rm -rf /opt/kafka-consumer/connections/$CONNECTION_NAME; fi; echo 'Service removal completed'"

execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$remove_service_commands" "Stop and remove service"

print_success "Service stopped and removed"

# Step 4: Note about ClickHouse table preservation
print_status "Step 4: ClickHouse table preservation..."
print_status "ClickHouse table will be preserved - data remains available for analysis"

# Step 5: List remaining connections
print_status "Step 5: Listing remaining connections..."
list_remaining_commands="echo 'Remaining Kafka consumer services:'; sudo systemctl list-unit-files | grep kafka-consumer || echo 'No remaining Kafka consumer services'; echo ''; echo 'Remaining connection directories:'; ls -la /opt/kafka-consumer/connections/ 2>/dev/null || echo 'No remaining connection directories'"

execute_ssm_command "$KAFKA_CONSUMER_INSTANCE_ID" "$list_remaining_commands" "List remaining connections"

print_success "Connection '$CONNECTION_NAME' successfully removed!"
print_status "Removal Summary:"
print_status "  - Connection Name: $CONNECTION_NAME"
print_status "  - Service: kafka-consumer-$CONNECTION_NAME (stopped and removed)"
print_status "  - Directory: /opt/kafka-consumer/connections/$CONNECTION_NAME (removed)"
print_status "  - ClickHouse Table: preserved (data remains available for analysis)" 
