resource "aws_vpc" "clickhouse_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "clickhouse-vpc"
  })
}

resource "aws_internet_gateway" "clickhouse_igw" {
  vpc_id = aws_vpc.clickhouse_vpc.id

  tags = merge(var.tags, {
    Name = "clickhouse-igw"
  })
}

resource "aws_subnet" "clickhouse_subnet" {
  vpc_id                  = aws_vpc.clickhouse_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_region.current.name}a"

  tags = merge(var.tags, {
    Name = "clickhouse-subnet"
  })
}

resource "aws_route_table" "clickhouse_rt" {
  vpc_id = aws_vpc.clickhouse_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.clickhouse_igw.id
  }

  tags = merge(var.tags, {
    Name = "clickhouse-rt"
  })
}

resource "aws_route_table_association" "clickhouse_rta" {
  subnet_id      = aws_subnet.clickhouse_subnet.id
  route_table_id = aws_route_table.clickhouse_rt.id
}

resource "aws_security_group" "clickhouse_sg" {
  name        = "clickhouse-sg"
  description = "Security group for ClickHouse instance"
  vpc_id      = aws_vpc.clickhouse_vpc.id

  ingress {
    from_port   = 8123
    to_port     = 8123
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.clickhouse_subnet.cidr_block]
  }

  # Allow native protocol from within VPC
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "clickhouse-sg"
  })
}

resource "aws_security_group" "grafana_sg" {
  name        = "grafana-sg"
  description = "Security group for Grafana instance"
  vpc_id      = aws_vpc.clickhouse_vpc.id

  # Allow HTTP access to Grafana from anywhere (for testing)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all egress traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "grafana-sg"
  })
}

# Security group for Web App EC2 instance
resource "aws_security_group" "web_app_sg" {
  name        = "web-app-sg"
  description = "Security group for Web App EC2 instance"
  vpc_id      = aws_vpc.clickhouse_vpc.id

  # Allow HTTP access to Aurora app on port 8000
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound to any Kafka brokers on port 9093 (for dynamic connections)
  egress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound to ClickHouse on port 9000 (native protocol)
  egress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.clickhouse_sg.id]
  }

  # Allow outbound to ClickHouse on port 8123 (HTTP interface)
  egress {
    from_port       = 8123
    to_port         = 8123
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
    Name = "web-app-sg"
  })
} 
