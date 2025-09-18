# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Security group for Kafka Consumer instance
resource "aws_security_group" "kafka_consumer_sg" {
  name        = "kafka-consumer-sg"
  description = "Security group for Kafka Consumer instance"
  vpc_id      = aws_vpc.clickhouse_vpc.id

  # Allow outbound to any Kafka brokers on port 9093 (for dynamic connections)
  egress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound to ClickHouse on port 9000
  egress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.clickhouse_sg.id]
  }

  # Allow HTTPS for package downloads and AWS API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP for package downloads
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow DNS
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow NTP
  egress {
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "kafka-consumer-sg"
  })
}

# Kafka Consumer EC2 instance
resource "aws_instance" "kafka_consumer" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_types.consumer

  subnet_id                   = aws_subnet.clickhouse_subnet.id
  vpc_security_group_ids      = [aws_security_group.kafka_consumer_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.kafka_consumer_profile.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/../scripts/kafka_consumer_prerequisites.sh", {
    ch_host              = aws_instance.clickhouse.private_ip
    ch_user              = "default"
    region               = data.aws_region.current.name
  }))

  tags = merge(var.tags, {
    Name = "kafka-consumer"
  })

  depends_on = [aws_instance.clickhouse]
}
