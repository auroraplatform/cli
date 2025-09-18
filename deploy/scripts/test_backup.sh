#!/bin/bash

# Test script for ClickHouse S3 backup functionality
# This script can be run on the ClickHouse instance to test the backup system

set -e

echo "🧪 Testing ClickHouse S3 Backup System"
echo "======================================"

# Check if we're on the ClickHouse instance
if [ ! -f "/opt/scripts/clickhouse_backup.sh" ]; then
    echo "❌ Error: Backup script not found. Make sure you're running this on the ClickHouse instance."
    exit 1
fi

echo "✅ Backup script found at /opt/scripts/clickhouse_backup.sh"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ Error: AWS CLI not found. Please install AWS CLI v2."
    exit 1
fi

echo "✅ AWS CLI is installed"

# Check if ClickHouse is running
if ! systemctl is-active --quiet clickhouse-server; then
    echo "❌ Error: ClickHouse server is not running."
    exit 1
fi

echo "✅ ClickHouse server is running"

# Test ClickHouse connection
if ! clickhouse-client --query "SELECT 1" &> /dev/null; then
    echo "❌ Error: Cannot connect to ClickHouse."
    exit 1
fi

echo "✅ ClickHouse connection successful"

# Get S3 bucket name from SSM
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
S3_BUCKET=$(aws ssm get-parameter --name "/aurora/clickhouse-backup-bucket" --region "$AWS_REGION" --query "Parameter.Value" --output text 2>/dev/null || echo "")

if [ -z "$S3_BUCKET" ]; then
    echo "❌ Error: Could not retrieve S3 bucket name from SSM Parameter Store."
    exit 1
fi

echo "✅ S3 bucket name retrieved: $S3_BUCKET"

# Test S3 access
if ! aws s3 ls "s3://$S3_BUCKET" &> /dev/null; then
    echo "❌ Error: Cannot access S3 bucket: $S3_BUCKET"
    exit 1
fi

echo "✅ S3 bucket access successful"

# Create a test database and table if they don't exist
echo "📊 Creating test data..."
clickhouse-client --query "CREATE DATABASE IF NOT EXISTS test_backup_db"
clickhouse-client --query "CREATE TABLE IF NOT EXISTS test_backup_db.test_table (id UInt32, name String, created_at DateTime DEFAULT now()) ENGINE = MergeTree() ORDER BY id"
clickhouse-client --query "INSERT INTO test_backup_db.test_table (id, name) VALUES (1, 'test_record_1'), (2, 'test_record_2'), (3, 'test_record_3')"

echo "✅ Test data created"

# Run the backup script
echo "🔄 Running backup script..."
if /opt/scripts/clickhouse_backup.sh; then
    echo "✅ Backup script executed successfully"
else
    echo "❌ Error: Backup script failed"
    exit 1
fi

# Check if backup was uploaded to S3
echo "🔍 Checking S3 for backup files..."
BACKUP_FILES=$(aws s3 ls "s3://$S3_BUCKET/backups/" --recursive | grep "clickhouse_backup_" | wc -l)

if [ "$BACKUP_FILES" -gt 0 ]; then
    echo "✅ Found $BACKUP_FILES backup file(s) in S3"
    echo "📁 Latest backup files:"
    aws s3 ls "s3://$S3_BUCKET/backups/" --recursive | grep "clickhouse_backup_" | tail -3
else
    echo "❌ Error: No backup files found in S3"
    exit 1
fi

# Check backup log
if [ -f "/var/log/clickhouse_backup.log" ]; then
    echo "📋 Recent backup log entries:"
    tail -10 /var/log/clickhouse_backup.log
else
    echo "⚠️  Warning: Backup log file not found"
fi

# Clean up test data
echo "🧹 Cleaning up test data..."
clickhouse-client --query "DROP DATABASE IF EXISTS test_backup_db"

echo ""
echo "🎉 Backup system test completed successfully!"
echo "💡 The backup system is working correctly and will run daily at 2 AM"
echo "📝 Backup logs are available at: /var/log/clickhouse_backup.log"
echo "🗂️  Backups are stored in S3 bucket: $S3_BUCKET"
