## Overview

This repository contains the automated deployment process for Aurora, a data streaming platform designed to process and visualize real-time event streams from Kafka to ClickHouse.

## Infrastructure Overview

The platform deploys the following key components:

- ClickHouse database on EC2
- Grafana dashboard on EC2  
- Kafka consumer on EC2
- Aurora web application on EC2 (Docker container)
- S3 bucket for automated ClickHouse backups
- VPC and security groups
- SSM Parameter Store for configuration

## Deployment and Management

The platform uses Terraform to manage infrastructure as code, allowing for consistent, repeatable deployments and easy management of AWS resources.

### Prerequisites

- An AWS account
- [AWS CLI installed and configured](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) with the appropriate credentials and region
- Terraform installed
- OpenAI API key

### Installation

Install via npm:

```bash
npm install -g aurora-platform-cli
```

### Deploying Infrastructure

To deploy the infrastructure, run:

```bash
aurora deploy
```

This script will:
1. Initialize and apply Terraform configuration
2. Deploy all EC2 instances and networking
3. Run post-deployment configuration scripts
4. Provide access URLs for all services

### Accessing Services

After deployment, you’ll receive a link to your Aurora web app.

### Destroying Infrastructure

To tear down the infrastructure, run:

```bash
aurora destroy
```

This script will:
1. Use Terraform to destroy all resources
2. Clean up local state files

**Note**: Destroying the infrastructure will remove all related resources and data. This action cannot be undone, so please use with caution.
