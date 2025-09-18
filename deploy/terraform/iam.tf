# IAM role for Kafka Consumer instance
resource "aws_iam_role" "kafka_consumer_role" {
  name = "kafka-consumer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "kafka-consumer-role"
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "kafka_consumer_profile" {
  name = "kafka-consumer-profile"
  role = aws_iam_role.kafka_consumer_role.name
}

# Policy for SSM parameter access (for dynamic Kafka configuration)
resource "aws_iam_policy" "ssm_parameter_access" {
  name        = "kafka-consumer-ssm-access"
  description = "Allow access to SSM parameters for Kafka Consumer"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/kafka-consumer/*"
        ]
      }
    ]
  })
}

# Policy for SSM Session Manager (replaces SSH access)
resource "aws_iam_policy" "ssm_session_manager" {
  name        = "kafka-consumer-ssm-session-manager"
  description = "Allow SSM Session Manager access for Kafka Consumer"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetConnectionStatus",
          "ssm:StartSession"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach policies to the role
resource "aws_iam_role_policy_attachment" "ssm_parameter_access_attachment" {
  role       = aws_iam_role.kafka_consumer_role.name
  policy_arn = aws_iam_policy.ssm_parameter_access.arn
}

resource "aws_iam_role_policy_attachment" "ssm_session_manager_attachment" {
  role       = aws_iam_role.kafka_consumer_role.name
  policy_arn = aws_iam_policy.ssm_session_manager.arn
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# IAM role for Web App EC2 instance
resource "aws_iam_role" "web_app_role" {
  name = "web-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "web-app-role"
  })
}

# IAM instance profile for Web App
resource "aws_iam_instance_profile" "web_app_profile" {
  name = "web-app-profile"
  role = aws_iam_role.web_app_role.name
}

# Policy for SSM Session Manager access for Web App
resource "aws_iam_policy" "web_app_ssm_session_manager" {
  name        = "web-app-ssm-session-manager"
  description = "Allow SSM Session Manager access for Web App"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetConnectionStatus",
          "ssm:StartSession"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach SSM Session Manager policy to Web App role
resource "aws_iam_role_policy_attachment" "web_app_ssm_session_manager_attachment" {
  role       = aws_iam_role.web_app_role.name
  policy_arn = aws_iam_policy.web_app_ssm_session_manager.arn
}

# Policy for SSM parameter access (for Aurora environment variables)
resource "aws_iam_policy" "web_app_ssm_parameter_access" {
  name        = "web-app-ssm-parameter-access"
  description = "Allow access to SSM parameters for Aurora application"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/aurora/*"
        ]
      }
    ]
  })
}

# Attach SSM parameter access policy to Web App role
resource "aws_iam_role_policy_attachment" "web_app_ssm_parameter_access_attachment" {
  role       = aws_iam_role.web_app_role.name
  policy_arn = aws_iam_policy.web_app_ssm_parameter_access.arn
} 

# IAM role for ClickHouse instance
resource "aws_iam_role" "clickhouse_role" {
  name = "clickhouse-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "clickhouse-role"
  })
}

# IAM instance profile for ClickHouse
resource "aws_iam_instance_profile" "clickhouse_profile" {
  name = "clickhouse-profile"
  role = aws_iam_role.clickhouse_role.name
}

# Policy for SSM Session Manager access for ClickHouse
resource "aws_iam_policy" "clickhouse_ssm_session_manager" {
  name        = "clickhouse-ssm-session-manager"
  description = "Allow SSM Session Manager access for ClickHouse"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetConnectionStatus",
          "ssm:StartSession"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach SSM Session Manager policy to ClickHouse role
resource "aws_iam_role_policy_attachment" "clickhouse_ssm_session_manager_attachment" {
  role       = aws_iam_role.clickhouse_role.name
  policy_arn = aws_iam_policy.clickhouse_ssm_session_manager.arn
}

# IAM role for Grafana instance
resource "aws_iam_role" "grafana_role" {
  name = "grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "grafana-role"
  })
}

# IAM instance profile for Grafana
resource "aws_iam_instance_profile" "grafana_profile" {
  name = "grafana-profile"
  role = aws_iam_role.grafana_role.name
}

# Policy for SSM Session Manager access for Grafana
resource "aws_iam_policy" "grafana_ssm_session_manager" {
  name        = "grafana-ssm-session-manager"
  description = "Allow SSM Session Manager access for Grafana"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "ssm:GetConnectionStatus",
          "ssm:StartSession"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach SSM Session Manager policy to Grafana role
resource "aws_iam_role_policy_attachment" "grafana_ssm_session_manager_attachment" {
  role       = aws_iam_role.grafana_role.name
  policy_arn = aws_iam_policy.grafana_ssm_session_manager.arn
}
