#!/bin/bash

# ClickHouse S3 Backup Script
# This script creates a backup of ClickHouse databases and uploads them to S3

set -e

# Configuration
BACKUP_DIR="/tmp/clickhouse_backups"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/clickhouse_backup.log"

# Get S3 bucket name from SSM Parameter Store
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
S3_BUCKET=$(aws ssm get-parameter --name "/aurora/clickhouse-backup-bucket" --region "$AWS_REGION" --query "Parameter.Value" --output text)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR"
        log "Cleaned up temporary backup directory: $BACKUP_DIR"
    fi
}

# Set up trap for cleanup on exit
trap cleanup EXIT

log "Starting ClickHouse backup process..."

# Create backup directory
mkdir -p "$BACKUP_DIR"
log "Created backup directory: $BACKUP_DIR"

# Get list of databases (excluding system databases)
DATABASES=$(clickhouse-client --query "SHOW DATABASES" | grep -v -E "^(system|information_schema|INFORMATION_SCHEMA)$" || true)

if [ -z "$DATABASES" ]; then
    log "No user databases found to backup"
    exit 0
fi

log "Found databases to backup: $DATABASES"

# Create backup for each database
for db in $DATABASES; do
    log "Backing up database: $db"
    
    # Create database backup directory
    DB_BACKUP_DIR="$BACKUP_DIR/$db"
    mkdir -p "$DB_BACKUP_DIR"
    
    # Get list of tables in the database
    TABLES=$(clickhouse-client --query "SHOW TABLES FROM $db" || true)
    
    if [ -z "$TABLES" ]; then
        log "No tables found in database: $db"
        continue
    fi
    
    log "Found tables in $db: $TABLES"
    
    # Backup each table
    for table in $TABLES; do
        log "Backing up table: $db.$table"
        
        # Create table backup using SELECT INTO OUTFILE
        BACKUP_FILE="$DB_BACKUP_DIR/${table}.sql"
        clickhouse-client --query "SELECT * FROM $db.$table FORMAT Native" > "$BACKUP_FILE" || {
            log "ERROR: Failed to backup table $db.$table"
            continue
        }
        
        # Get table schema
        SCHEMA_FILE="$DB_BACKUP_DIR/${table}_schema.sql"
        clickhouse-client --query "SHOW CREATE TABLE $db.$table" > "$SCHEMA_FILE" || {
            log "ERROR: Failed to get schema for table $db.$table"
        }
        
        log "Successfully backed up table: $db.$table"
    done
done

# Create a compressed archive of the backup
BACKUP_ARCHIVE="$BACKUP_DIR/clickhouse_backup_$DATE.tar.gz"
cd "$BACKUP_DIR"
tar -czf "$BACKUP_ARCHIVE" --exclude="clickhouse_backup_*.tar.gz" . || {
    log "ERROR: Failed to create backup archive"
    exit 1
}

log "Created backup archive: $BACKUP_ARCHIVE"

# Upload to S3
S3_KEY="backups/clickhouse_backup_$DATE.tar.gz"
log "Uploading backup to S3: s3://$S3_BUCKET/$S3_KEY"

aws s3 cp "$BACKUP_ARCHIVE" "s3://$S3_BUCKET/$S3_KEY" || {
    log "ERROR: Failed to upload backup to S3"
    exit 1
}

log "Successfully uploaded backup to S3: s3://$S3_BUCKET/$S3_KEY"

# Get backup file size for logging
BACKUP_SIZE=$(du -h "$BACKUP_ARCHIVE" | cut -f1)
log "Backup completed successfully. Size: $BACKUP_SIZE"

# Clean up old local backups (keep only last 3 days)
find /tmp -name "clickhouse_backup_*.tar.gz" -mtime +3 -delete 2>/dev/null || true

log "ClickHouse backup process completed successfully"
