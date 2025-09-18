variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "kafka_brokers" {
  description = "List of Kafka broker endpoints"
  type        = list(string)
  default     = []
}

variable "kafka_topic" {
  description = "Kafka topic to consume from"
  type        = string
  default     = ""
}

variable "kafka_user_ssm_path" {
  description = "SSM parameter path for Kafka SASL username"
  type        = string
  default     = ""
}

variable "kafka_pass_ssm_path" {
  description = "SSM parameter path for Kafka SASL password"
  type        = string
  default     = ""
}

variable "ch_password_ssm_path" {
  description = "SSM parameter path for ClickHouse password"
  type        = string
  default     = ""
}

variable "ch_host" {
  description = "ClickHouse host endpoint (leave empty to use deployed ClickHouse instance)"
  type        = string
  default     = ""
}

variable "ch_user" {
  description = "ClickHouse username (leave empty to use default user)"
  type        = string
  default     = ""
}

variable "kafka_cidrs" {
  description = "List of Kafka broker IP CIDRs (optional, leave empty to allow any internet-accessible Kafka cluster)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

variable "instance_types" {
  description = "Instance types for various components"
  type = object({
    clickhouse = string
    grafana    = string
    consumer   = string
    web_app    = string
  })
}

variable "openai_api_key" {
  description = "OpenAI API key for the Aurora application"
  type        = string
  default     = ""
} 
