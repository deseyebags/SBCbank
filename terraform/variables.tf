variable "alb_domain_name" {
  description = "Domain name for the ALB ACM certificate"
  type        = string
  default     = ""
}
variable "project_name" {
  description = "Short name used as a prefix for all resource names."
  type        = string
  default     = "sbcbank"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "ap-southeast-1"
}

# ── Networking ──────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ── Database ─────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance type."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version for the RDS instance."
  type        = string
  default     = "16.3"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "sbcbank"
}

variable "db_username" {
  description = "Master username for the RDS instance."
  type        = string
  default     = "sbcadmin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the RDS instance. Set via TF_VAR_db_password env var."
  type        = string
  sensitive   = true
}

# ── Cache ─────────────────────────────────────────────────────────────────────

variable "redis_node_type" {
  description = "ElastiCache node type for the Redis cluster."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "Redis engine version for the ElastiCache cluster."
  type        = string
  default     = "7.1"
}

# ── Container workloads ───────────────────────────────────────────────────────

variable "ecs_task_cpu" {
  description = "Default CPU units for ECS Fargate tasks (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "ecs_task_memory" {
  description = "Default memory (MiB) for ECS Fargate tasks."
  type        = number
  default     = 512
}

# LocalStack toggle (set to true for local development)
variable "use_localstack" {
  description = "Set to true to use LocalStack endpoints for local development."
  type        = bool
  default     = false
}

# ── IAM Governance ──────────────────────────────────────────────────────────

variable "enable_human_iam_roles" {
  description = "Create human-access IAM roles (admin, devops, auditor, support)."
  type        = bool
  default     = true
}

variable "human_iam_role_principal_arns" {
  description = "AWS principal ARNs allowed to assume human-access roles. Defaults to account root if empty."
  type        = list(string)
  default     = []
}

variable "enable_kms_customer_managed_keys" {
  description = "Create customer-managed KMS keys and use them for sensitive data and logs."
  type        = bool
  default     = true
}

variable "enable_identity_center" {
  description = "Enable IAM Identity Center permission sets (requires identity_center_instance_arn)."
  type        = bool
  default     = false
}

variable "identity_center_instance_arn" {
  description = "IAM Identity Center instance ARN used to create permission sets."
  type        = string
  default     = ""
}

variable "enable_organizations_governance" {
  description = "Enable Organizations SCP creation and optional attachment to a root/OU/account target."
  type        = bool
  default     = false
}

variable "organizations_scp_target_id" {
  description = "Organizations target ID (root/OU/account) for SCP attachment. Leave empty to create SCPs without attachments."
  type        = string
  default     = ""
}

# ── Cognito ──────────────────────────────────────────────────────────────────

variable "cognito_user_pool_name" {
  description = "Name for the Cognito user pool."
  type        = string
  default     = "sbcbank-user-pool"
}

variable "cognito_identity_pool_name" {
  description = "Name for the Cognito identity pool."
  type        = string
  default     = "sbcbank-identity-pool"
}

# ── Lambda ───────────────────────────────────────────────────────────────────

variable "notification_lambda_handler" {
  description = "Handler for the notification Lambda function."
  type        = string
  default     = "notification_lambda.handler"
}

variable "fraud_lambda_handler" {
  description = "Handler for the fraud Lambda function."
  type        = string
  default     = "fraud_lambda.handler"
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions."
  type        = string
  default     = "python3.9"
}

variable "notification_lambda_s3_key" {
  description = "S3 object key for notification Lambda deployment package."
  type        = string
  default     = "notification_lambda.zip"
}

variable "fraud_lambda_s3_key" {
  description = "S3 object key for fraud Lambda deployment package."
  type        = string
  default     = "fraud_lambda.zip"
}

# ── EventBridge ──────────────────────────────────────────────────────────────

variable "eventbridge_bus_name" {
  description = "Name for the EventBridge event bus."
  type        = string
  default     = "sbcbank-event-bus"
}

# ── Fraud Detector ───────────────────────────────────────────────────────────

variable "fraud_detector_id" {
  description = "ID for the Fraud Detector."
  type        = string
  default     = "sbcbank-fraud-detector"
}

# ── Compliance Analytics (Athena + CloudWatch) ─────────────────────────────

variable "compliance_metrics_namespace" {
  description = "CloudWatch namespace for compliance custom metrics."
  type        = string
  default     = "SBCBank/Compliance"
}

variable "compliance_glue_database_name" {
  description = "Glue database name for compliance analytics datasets."
  type        = string
  default     = "sbcbank_compliance"
}

variable "compliance_glue_table_name" {
  description = "Glue table name that stores compliance metric snapshots."
  type        = string
  default     = "compliance_snapshots"
}
