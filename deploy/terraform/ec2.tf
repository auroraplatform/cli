resource "aws_instance" "clickhouse" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_types.clickhouse

  subnet_id                   = aws_subnet.clickhouse_subnet.id
  vpc_security_group_ids      = [aws_security_group.clickhouse_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.clickhouse_profile.name

  root_block_device {
    volume_size = 20  # GB
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              yum update -y

              # Install SSM agent (should already be installed on Amazon Linux 2)
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              # Add ClickHouse official repo using the official repo file
              sudo yum install -y yum-utils
              sudo yum-config-manager --add-repo https://packages.clickhouse.com/rpm/clickhouse.repo
              sudo yum install -y clickhouse-server clickhouse-client

              # Fix listen_host: only set 0.0.0.0, not ::/0, and avoid for interserver_http_port
              # Remove all listen_host lines first
              sed -i '/<listen_host>/d' /etc/clickhouse-server/config.xml
              # Insert <listen_host>0.0.0.0</listen_host> just before </http_port> if not present
              if ! grep -q '<listen_host>0.0.0.0</listen_host>' /etc/clickhouse-server/config.xml; then
                sed -i '/<http_port>.*<\/http_port>/a \\n    <listen_host>0.0.0.0</listen_host>' /etc/clickhouse-server/config.xml
              fi
              # Do NOT add listen_host for interserver_http_port
              sudo systemctl restart clickhouse-server
              # Print the relevant config and status for debugging
              awk '/<http_port>/,/<\/http_port>/' /etc/clickhouse-server/config.xml
              sudo systemctl status clickhouse-server

              # Allow remote connections for default user (no password)
              cat > /etc/clickhouse-server/users.d/remote.xml << 'CONF'
              <yandex>
                <users>
                  <default>
                    <networks>
                      <ip>::/0</ip>
                      <ip>0.0.0.0/0</ip>
                    </networks>
                  </default>
                </users>
              </yandex>
              CONF

              systemctl enable clickhouse-server
              systemctl start clickhouse-server

              # Wait for ClickHouse HTTP interface to be ready
              for i in {1..30}; do
                if clickhouse-client --host localhost --query "SELECT 1"; then
                  echo "ClickHouse is up!"
                  break
                fi
                echo "Waiting for ClickHouse to be ready... ($i)"
                sleep 2
              done

              # Install AWS CLI v2 for S3 backup functionality
              echo "Installing AWS CLI v2..."
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install
              rm -rf aws awscliv2.zip

              # Create backup script directory
              mkdir -p /opt/scripts
              chown ec2-user:ec2-user /opt/scripts

              # Create the backup script
              cat > /opt/scripts/clickhouse_backup.sh << 'BACKUP_SCRIPT'
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
                      BACKUP_FILE="$$DB_BACKUP_DIR/$${table}.sql"
                      clickhouse-client --query "SELECT * FROM $$db.$$table FORMAT Native" > "$$BACKUP_FILE" || {
                          log "ERROR: Failed to backup table $$db.$$table"
                          continue
                      }
                      
                      # Get table schema
                      SCHEMA_FILE="$$DB_BACKUP_DIR/$${table}_schema.sql"
                      clickhouse-client --query "SHOW CREATE TABLE $$db.$$table" > "$$SCHEMA_FILE" || {
                          log "ERROR: Failed to get schema for table $$db.$$table"
                      }
                      
                      log "Successfully backed up table: $$db.$$table"
                  done
              done

              # Create a compressed archive of the backup
              BACKUP_ARCHIVE="$$BACKUP_DIR/clickhouse_backup_$$DATE.tar.gz"
              cd "$$BACKUP_DIR"
              tar -czf "$$BACKUP_ARCHIVE" --exclude="clickhouse_backup_*.tar.gz" . || {
                  log "ERROR: Failed to create backup archive"
                  exit 1
              }

              log "Created backup archive: $$BACKUP_ARCHIVE"

              # Upload to S3
              S3_KEY="backups/clickhouse_backup_$$DATE.tar.gz"
              log "Uploading backup to S3: s3://$$S3_BUCKET/$$S3_KEY"

              aws s3 cp "$$BACKUP_ARCHIVE" "s3://$$S3_BUCKET/$$S3_KEY" || {
                  log "ERROR: Failed to upload backup to S3"
                  exit 1
              }

              log "Successfully uploaded backup to S3: s3://$$S3_BUCKET/$$S3_KEY"

              # Get backup file size for logging
              BACKUP_SIZE=$$(du -h "$$BACKUP_ARCHIVE" | cut -f1)
              log "Backup completed successfully. Size: $$BACKUP_SIZE"

              # Clean up old local backups (keep only last 3 days)
              find /tmp -name "clickhouse_backup_*.tar.gz" -mtime +3 -delete 2>/dev/null || true

              log "ClickHouse backup process completed successfully"
              BACKUP_SCRIPT

              # Make the backup script executable
              chmod +x /opt/scripts/clickhouse_backup.sh

              # Set up cron job for daily backups at 2 AM
              echo "0 2 * * * /opt/scripts/clickhouse_backup.sh" | crontab -

              echo "ClickHouse backup system configured successfully"
              EOF

  tags = merge(var.tags, {
    Name = "clickhouse-server"
  })
}


resource "aws_instance" "grafana" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_types.grafana

  subnet_id                   = aws_subnet.clickhouse_subnet.id
  vpc_security_group_ids      = [aws_security_group.grafana_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.grafana_profile.name
  depends_on                  = [aws_instance.clickhouse]

  user_data = base64encode(<<-EOF
  #!/bin/bash
  exec > >(tee -i /var/log/user-data.log)
  exec 2>&1

  yum update -y
  yum install -y jq wget

  # Install SSM agent (should already be installed on Amazon Linux 2)
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent

  # Install Grafana using a compatible version for Amazon Linux 2
  echo "Installing Grafana..."
  
  # Method 1: Try installing from RPM directly (compatible version)
  if ! yum install -y grafana; then
    echo "Standard Grafana installation failed, trying alternative method..."
    
    # Method 2: Download and install a compatible version manually
    cd /tmp
    wget https://dl.grafana.com/oss/release/grafana-8.5.21-1.x86_64.rpm
    yum install -y grafana-8.5.21-1.x86_64.rpm
    rm -f grafana-8.5.21-1.x86_64.rpm
  fi

  # Verify Grafana is installed
  if ! command -v grafana-server &> /dev/null; then
    echo "ERROR: Grafana installation failed completely"
    exit 1
  fi

  echo "Grafana installed successfully"

  # Install ClickHouse plugin (per official docs)
  echo "Installing ClickHouse plugin..."
  grafana-cli plugins install grafana-clickhouse-datasource

  # Ensure provisioning directory exists
  mkdir -p /etc/grafana/provisioning/datasources

  # Write ClickHouse datasource provisioning YAML
  cat <<EOD > /etc/grafana/provisioning/datasources/clickhouse.yaml
  apiVersion: 1
  datasources:
    - name: ClickHouse
      type: grafana-clickhouse-datasource
      access: proxy
      url: http://${aws_instance.clickhouse.private_ip}:8123
      database: demo
      isDefault: true
      jsonData:
        protocol: http
        server: ${aws_instance.clickhouse.private_ip}
        port: 8123
  EOD

  # Debug: print the YAML file contents and directory listing
  echo "--- /etc/grafana/provisioning/datasources/clickhouse.yaml ---"
  cat /etc/grafana/provisioning/datasources/clickhouse.yaml
  echo "--- Directory listing ---"
  ls -l /etc/grafana/provisioning/datasources/

  # Set correct permissions (ensure grafana user exists first)
  if id "grafana" &>/dev/null; then
    chown -R grafana:grafana /etc/grafana/provisioning/datasources
    echo "Permissions set successfully"
  else
    echo "WARNING: grafana user not found, creating it..."
    useradd -r -s /bin/false grafana
    chown -R grafana:grafana /etc/grafana/provisioning/datasources
  fi

  # Enable and start Grafana
  echo "Starting Grafana service..."
  systemctl daemon-reload
  systemctl enable grafana-server
  systemctl restart grafana-server

  # Wait for Grafana to start
  echo "Waiting for Grafana to start..."
  for i in {1..30}; do
    if systemctl is-active --quiet grafana-server; then
      echo "Grafana is running!"
      break
    fi
    echo "Waiting for Grafana to start... ($i/30)"
    sleep 2
  done

  # Debug: print last 50 lines of Grafana log
  echo "--- Last 50 lines of /var/log/grafana/grafana.log ---"
  if [ -f /var/log/grafana/grafana.log ]; then
    tail -n 50 /var/log/grafana/grafana.log
  else
    echo "Grafana log file not found yet"
  fi

  # Check service status
  echo "--- Grafana service status ---"
  systemctl status grafana-server --no-pager

  echo "Grafana setup complete!"
  EOF
  )

  tags = merge(var.tags, {
    Name = "grafana-server"
  })
}

# Note: Outputs are defined in outputs.tf 

# Web App EC2 instance for running connect-ec2.sh
resource "aws_instance" "web_app" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_types.web_app

  subnet_id                   = aws_subnet.clickhouse_subnet.id
  vpc_security_group_ids      = [aws_security_group.web_app_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.web_app_profile.name

  root_block_device {
    volume_size = 20  # GB
    volume_type = "gp3"
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e
              yum update -y

              # Install Docker
              yum install -y docker
              systemctl enable docker
              systemctl start docker
              usermod -a -G docker ec2-user

              # Install AWS CLI v2
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install
              rm -rf aws awscliv2.zip

              # Install Python 3 and pip
              yum install -y python3 python3-pip

              # Install required Python packages
              pip3 install boto3 clickhouse-driver kafka-python

              # Install Terraform
              yum install -y yum-utils
              yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
              yum -y install terraform

              # Create terraform directory and copy terraform files
              mkdir -p /opt/terraform
              chown ec2-user:ec2-user /opt/terraform

              # Create scripts directory
              mkdir -p /opt/scripts
              chown ec2-user:ec2-user /opt/scripts

              # Install SSM agent (should already be installed on Amazon Linux 2)
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent

              # Wait for Docker to be ready
              echo "Waiting for Docker to be ready..."
              for i in {1..30}; do
                if docker info >/dev/null 2>&1; then
                  echo "Docker is ready!"
                  break
                fi
                echo "Waiting for Docker... ($i/30)"
                sleep 2
              done

              # Pull and run the Aurora container
              echo "Pulling Docker image..."
              docker pull miyasatoka/aurora-web-app:latest

              # Create .env file placeholder (will be populated later)
                                    cat > /home/ec2-user/.env << 'ENVFILE'
              # Environment variables for Aurora app
              # Add your configuration here
              ENVFILE

              # Run the Aurora container
              echo "Starting Aurora container..."
              docker run -d -p 8000:8000 \
                -v /opt/scripts:/opt/scripts \
                -v /opt/terraform:/opt/terraform \
                -e AWS_DEFAULT_REGION=${data.aws_region.current.name} \
                -e CLICKHOUSE_HOST=$(aws ssm get-parameter --name "/aurora/clickhouse-host" --with-decryption --query "Parameter.Value" --output text --region ${data.aws_region.current.name}) \
                -e CLICKHOUSE_USER=default \
                -e CLICKHOUSE_PASSWORD="" \
                -e OPENAI_API_KEY=$(aws ssm get-parameter --name "/aurora/openai-api-key" --with-decryption --query "Parameter.Value" --output text --region ${data.aws_region.current.name}) \
                --name aurora miyasatoka/aurora-web-app:latest

              # Wait for container to be running
              echo "Waiting for container to start..."
              for i in {1..30}; do
                if docker ps | grep -q aurora; then
                  echo "Aurora container is running!"
                  break
                fi
                echo "Waiting for container... ($i/30)"
                sleep 2
              done

              # Check container status
              echo "Container status:"
              docker ps

              echo "Web App EC2 instance setup complete!"
              echo "Aurora app should be accessible at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"
              EOF
  )

  tags = merge(var.tags, {
    Name = "web-app-ec2"
  })

  depends_on = [aws_instance.clickhouse, aws_instance.kafka_consumer]
} 
