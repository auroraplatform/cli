terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

# Get current IP for security group
data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

# Get current AWS region
data "aws_region" "current" {}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Generate random suffix for unique resource names
resource "random_id" "deployment_suffix" {
  byte_length = 4
}

# Store OpenAI API key in SSM Parameter Store
resource "aws_ssm_parameter" "openai_api_key" {
  name        = "/aurora/openai-api-key"
  description = "OpenAI API key for Aurora application"
  type        = "SecureString"
  value       = var.openai_api_key

  tags = merge(var.tags, {
    Name = "openai-api-key"
  })
}

# Store ClickHouse host in SSM Parameter Store
resource "aws_ssm_parameter" "clickhouse_host" {
  name        = "/aurora/clickhouse-host"
  description = "ClickHouse host for Aurora application"
  type        = "String"
  value       = aws_instance.clickhouse.private_ip

  tags = merge(var.tags, {
    Name = "clickhouse-host"
  })
}

# Store Grafana URL in SSM Parameter Store
resource "aws_ssm_parameter" "grafana_url" {
  name        = "/aurora/grafana-url"
  description = "Grafana dashboard URL for Aurora application"
  type        = "String"
  value       = "http://${aws_instance.grafana.public_ip}:3000"

  tags = merge(var.tags, {
    Name = "grafana-url"
  })
}
