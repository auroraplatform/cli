output "clickhouse_public_ip" {
  description = "Public IP address of the ClickHouse server"
  value       = aws_instance.clickhouse.public_ip
}

output "clickhouse_private_ip" {
  description = "Private IP address of the ClickHouse server"
  value       = aws_instance.clickhouse.private_ip
}

output "grafana_public_ip" {
  description = "Public IP address of the Grafana server"
  value       = aws_instance.grafana.public_ip
}

output "kafka_consumer_public_ip" {
  description = "Public IP address of the Kafka consumer instance"
  value       = aws_instance.kafka_consumer.public_ip
}

output "kafka_consumer_private_ip" {
  description = "Private IP address of the Kafka consumer instance"
  value       = aws_instance.kafka_consumer.private_ip
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.clickhouse_vpc.id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = aws_subnet.clickhouse_subnet.id
}

output "grafana_url" {
  description = "URL to access Grafana dashboard"
  value       = "http://${aws_instance.grafana.public_ip}:3000"
}

output "clickhouse_connection_string" {
  description = "ClickHouse connection string for external clients"
  value       = "clickhouse://${aws_instance.clickhouse.private_ip}:9000"
}

# Additional outputs that were in ec2.tf
output "kafka_consumer_instance_id" {
  description = "Instance ID of the Kafka Consumer"
  value       = aws_instance.kafka_consumer.id
}

output "kafka_consumer_security_group_id" {
  description = "Security group ID of the Kafka Consumer"
  value       = aws_security_group.kafka_consumer_sg.id
}

output "kafka_consumer_iam_role_arn" {
  description = "IAM role ARN of the Kafka Consumer"
  value       = aws_iam_role.kafka_consumer_role.arn
}

# Web App EC2 outputs
output "web_app_public_ip" {
  description = "Public IP address of the Web App EC2 instance"
  value       = aws_instance.web_app.public_ip
}

output "web_app_private_ip" {
  description = "Private IP address of the Web App EC2 instance"
  value       = aws_instance.web_app.private_ip
}

output "web_app_instance_id" {
  description = "Instance ID of the Web App EC2"
  value       = aws_instance.web_app.id
}

output "web_app_security_group_id" {
  description = "Security group ID of the Web App EC2"
  value       = aws_security_group.web_app_sg.id
}

output "web_app_iam_role_arn" {
  description = "IAM role ARN of the Web App EC2"
  value       = aws_iam_role.web_app_role.arn
}

output "web_app_url" {
  description = "URL to access the Aurora web application"
        value       = "http://${aws_instance.web_app.public_ip}:8000"
}

# S3 Backup outputs
output "clickhouse_backup_bucket_name" {
  description = "Name of the S3 bucket used for ClickHouse backups"
  value       = aws_s3_bucket.clickhouse_backups.bucket
}

output "clickhouse_backup_bucket_arn" {
  description = "ARN of the S3 bucket used for ClickHouse backups"
  value       = aws_s3_bucket.clickhouse_backups.arn
} 

output "z_deployment_summary" {
  description = "Summary of the deployment"
  value = <<EOT
    🎉 Infrastructure Deployment Complete!

    📝 Next Steps:
    1. Access your Aurora web application at: http://${aws_instance.web_app.public_ip}:8000
    2. Access Grafana dashboard at: http://${aws_instance.grafana.public_ip}:3000 (username: admin, password: admin)
    
    💾 Backup System:
    - ClickHouse backups are automatically created daily at 2 AM
    - Backups are stored in S3 bucket: ${aws_s3_bucket.clickhouse_backups.bucket}
    - Backup logs are available at: /var/log/clickhouse_backup.log on the ClickHouse instance
  EOT
}
