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

# Get instance details from Terraform
cd terraform
WEB_APP_INSTANCE_ID=$(terraform output -raw web_app_instance_id 2>/dev/null || echo "")

if [ -z "$WEB_APP_INSTANCE_ID" ]; then
    print_error "Failed to get web-app-ec2 instance ID. Make sure Terraform is deployed and outputs are available."
    exit 1
fi

print_success "Web App EC2 Instance ID: $WEB_APP_INSTANCE_ID"

cd ..

# Step 1: Wait for instance to be ready
print_status "Step 1: Waiting for instance to be ready..."

# Wait for SSM to be available
print_status "Waiting for SSM to be available on $WEB_APP_INSTANCE_ID..."
for i in {1..30}; do
    if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$WEB_APP_INSTANCE_ID" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q "Online"; then
        print_success "SSM connection established"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "SSM connection failed after 30 attempts"
        exit 1
    fi
    print_status "Waiting for SSM... (attempt $i/30)"
    sleep 10
done

# Step 2: Copy scripts to the instance
print_status "Step 2: Copying scripts to web-app-ec2..."

# Create app user first
print_status "Creating app user..."
execute_ssm_command "$WEB_APP_INSTANCE_ID" "sudo useradd -m -s /bin/bash app || echo 'User app already exists'" "Create app user"

# Create scripts directory on the instance
execute_ssm_command "$WEB_APP_INSTANCE_ID" "sudo mkdir -p /opt/scripts && sudo chmod 777 /opt/scripts && sudo chown app:app /opt/scripts" "Create scripts directory with proper ownership"

# Copy connect-ec2.sh
print_status "Copying connect-ec2.sh..."
upload_file_via_ssm "$WEB_APP_INSTANCE_ID" "scripts/connect-ec2.sh" "/opt/scripts/connect-ec2.sh" "Upload connect-ec2.sh"
execute_ssm_command "$WEB_APP_INSTANCE_ID" "chmod 755 /opt/scripts/connect-ec2.sh && chown app:app /opt/scripts/connect-ec2.sh" "Make connect-ec2.sh executable and set ownership"

# Copy kafka_to_clickhouse.py
print_status "Copying kafka_to_clickhouse.py..."
upload_file_via_ssm "$WEB_APP_INSTANCE_ID" "scripts/kafka_to_clickhouse.py" "/opt/scripts/kafka_to_clickhouse.py" "Upload kafka_to_clickhouse.py"
execute_ssm_command "$WEB_APP_INSTANCE_ID" "chmod 755 /opt/scripts/kafka_to_clickhouse.py && chown app:app /opt/scripts/kafka_to_clickhouse.py" "Make kafka_to_clickhouse.py executable and set ownership"

# Copy disconnect.sh
print_status "Copying disconnect.sh..."
upload_file_via_ssm "$WEB_APP_INSTANCE_ID" "scripts/disconnect.sh" "/opt/scripts/disconnect.sh" "Upload disconnect.sh"
execute_ssm_command "$WEB_APP_INSTANCE_ID" "chmod 755 /opt/scripts/disconnect.sh && chown app:app /opt/scripts/disconnect.sh" "Make disconnect.sh executable and set ownership"

# Step 3: Create infra.env file
print_status "Step 3: Creating infra.env file..."
cd terraform

# Get infrastructure details from Terraform with better error handling
print_status "Getting infrastructure details from Terraform..."
KAFKA_CONSUMER_INSTANCE_ID=$(terraform output -raw kafka_consumer_instance_id 2>/dev/null || echo "")
CLICKHOUSE_PRIVATE_IP=$(terraform output -raw clickhouse_private_ip 2>/dev/null || echo "")

# Validate the values
if [ -z "$KAFKA_CONSUMER_INSTANCE_ID" ] || [ -z "$CLICKHOUSE_PRIVATE_IP" ]; then
    print_error "Failed to get infrastructure details for infra.env"
    print_error "KAFKA_CONSUMER_INSTANCE_ID: '$KAFKA_CONSUMER_INSTANCE_ID'"
    print_error "CLICKHOUSE_PRIVATE_IP: '$CLICKHOUSE_PRIVATE_IP'"
    print_error "Make sure Terraform is deployed and outputs are available."
    exit 1
fi

# Create infra.env file
cat > /tmp/infra.env << EOF
KAFKA_CONSUMER_INSTANCE_ID="$KAFKA_CONSUMER_INSTANCE_ID"
CLICKHOUSE_PRIVATE_IP="$CLICKHOUSE_PRIVATE_IP"
EOF

cd ..

# Create terraform directory on the instance
print_status "Creating terraform directory..."
execute_ssm_command "$WEB_APP_INSTANCE_ID" "sudo mkdir -p /opt/terraform && sudo chmod 755 /opt/terraform && sudo chown app:app /opt/terraform" "Create terraform directory with proper permissions"

upload_file_via_ssm "$WEB_APP_INSTANCE_ID" "/tmp/infra.env" "/opt/terraform/infra.env" "Upload infra.env"
execute_ssm_command "$WEB_APP_INSTANCE_ID" "chown app:app /opt/terraform/infra.env" "Set infra.env ownership"
rm -f /tmp/infra.env

# Set environment variable
execute_ssm_command "$WEB_APP_INSTANCE_ID" "echo 'export TERRAFORM_DIR=/opt/terraform' >> ~/.bashrc" "Set TERRAFORM_DIR environment variable"

# Step 4: Verify files were copied
print_status "Step 4: Verifying files were copied..."

if execute_ssm_command "$WEB_APP_INSTANCE_ID" "ls -la /opt/scripts/" "List scripts directory" && \
   execute_ssm_command "$WEB_APP_INSTANCE_ID" "ls -la /opt/terraform/" "List terraform directory"; then
    print_success "All files copied successfully!"
else
    print_error "Some files may not have been copied correctly"
    exit 1
fi
