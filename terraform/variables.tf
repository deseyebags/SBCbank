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
