#!/bin/bash

# Update system
yum update -y

# Install SSM agent (enables SSM Session Manager)
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install Python 3 and pip
yum install -y python3 python3-pip

# Install required Python packages
pip3 install kafka-python==2.2.15 clickhouse-driver==0.2.9 pytz==2025.2 tzlocal==5.3.1

# Create kafka-consumer user and group
groupadd -r kafka-consumer
useradd -r -g kafka-consumer -s /bin/false -d /opt/kafka-consumer kafka-consumer

# Create necessary directories
mkdir -p /opt/kafka-consumer/connections
mkdir -p /var/log/kafka-consumer
mkdir -p /var/lib/kafka-consumer

# Set proper ownership
chown -R kafka-consumer:kafka-consumer /opt/kafka-consumer
chown -R kafka-consumer:kafka-consumer /var/log/kafka-consumer
chown -R kafka-consumer:kafka-consumer /var/lib/kafka-consumer

# Set proper permissions
chmod 755 /opt/kafka-consumer
chmod 755 /opt/kafka-consumer/connections
chmod 755 /var/log/kafka-consumer
chmod 755 /var/lib/kafka-consumer

echo "Kafka Consumer infrastructure setup completed successfully!"
echo "SSM agent installed and enabled for secure remote management."
echo "Ready for manual connection setup using connect.sh script." 