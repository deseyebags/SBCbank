##############################################################################
# main.tf – SBCbank cloud-native infrastructure (starter template)
#
# Resources defined here are intentional stubs / scaffolding.  Service code
# (container images, Lambda packages, etc.) is NOT required at this stage.
# Fill in TODO comments as the project matures.
##############################################################################

locals {
  prefix = "${var.project_name}-${var.environment}"
  azs    = slice(data.aws_availability_zones.available.names, 0, 2)
  lambda_sources = {
    notification      = "${path.module}/../lambdas/notification_lambda.py"
    fraud             = "${path.module}/../lambdas/fraud_lambda.py"
    default_bus_probe = "${path.module}/../lambdas/default_bus_probe_lambda.py"
  }

  human_role_assume_principals = length(var.human_iam_role_principal_arns) > 0 ? var.human_iam_role_principal_arns : ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  identity_center_enabled          = var.enable_identity_center && length(trimspace(var.identity_center_instance_arn)) > 0 && !var.use_localstack
  organizations_governance_enabled = var.enable_organizations_governance && !var.use_localstack

  human_access_roles = {
    admin = {
      description         = "Administrative role for platform owners"
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    devops = {
      description = "DevOps role for infrastructure and deployment operations"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/PowerUserAccess",
        "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
      ]
    }
    auditor = {
      description = "Read-only security and compliance audit role"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/SecurityAudit",
        "arn:aws:iam::aws:policy/ReadOnlyAccess"
      ]
    }
    support_read_only = {
      description         = "Operational diagnostics role with read-only access"
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
  }

  human_access_role_policy_attachments = merge([
    for role_name, role_def in local.human_access_roles : {
      for policy_arn in role_def.managed_policy_arns :
      "${role_name}|${policy_arn}" => {
        role_name  = role_name
        policy_arn = policy_arn
      }
    }
  ]...)

  identity_center_permission_sets = {
    admin = {
      description      = "Administrative access for security-approved platform operators"
      session_duration = "PT4H"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ]
    }
    devops = {
      description      = "Infrastructure deployment and operations access"
      session_duration = "PT4H"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/PowerUserAccess",
        "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
      ]
    }
    auditor = {
      description      = "Read-only compliance and audit access"
      session_duration = "PT2H"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/SecurityAudit",
        "arn:aws:iam::aws:policy/ReadOnlyAccess"
      ]
    }
    support_read_only = {
      description      = "Read-only operational diagnostics access"
      session_duration = "PT2H"
      managed_policy_arns = [
        "arn:aws:iam::aws:policy/ReadOnlyAccess"
      ]
    }
  }

  identity_center_permission_set_policy_attachments = merge([
    for permission_set_name, definition in local.identity_center_permission_sets : {
      for policy_arn in definition.managed_policy_arns :
      "${permission_set_name}|${policy_arn}" => {
        permission_set_name = permission_set_name
        policy_arn          = policy_arn
      }
    }
  ]...)
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.prefix}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.prefix}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${local.prefix}-private-${local.azs[count.index]}" }
}

resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"
  tags   = { Name = "${local.prefix}-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${local.prefix}-nat-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = { Name = "${local.prefix}-private-rt-${count.index}" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "private_app" {
  name        = "${local.prefix}-private-app-sg"
  description = "Security group for private app tier (ECS tasks and API Gateway VPC Link ENIs)."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    self            = true
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-private-app-sg" }
}

resource "aws_security_group" "private_data" {
  name        = "${local.prefix}-private-data-sg"
  description = "Security group for private data tier (Aurora and Redis)."
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.prefix}-private-data-sg" }
}

resource "aws_security_group_rule" "private_app_to_data_postgres_egress" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_app.id
  source_security_group_id = aws_security_group.private_data.id
}

resource "aws_security_group_rule" "private_app_to_data_redis_egress" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_app.id
  source_security_group_id = aws_security_group.private_data.id
}

resource "aws_security_group_rule" "private_data_from_app_postgres_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_data.id
  source_security_group_id = aws_security_group.private_app.id
}

resource "aws_security_group_rule" "private_data_from_app_redis_ingress" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_data.id
  source_security_group_id = aws_security_group.private_app.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Edge/API protection (WAF)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_wafv2_web_acl" "api" {
  name  = "${local.prefix}-api-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.prefix}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefix}-api-web-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.prefix}-api-web-acl" }
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Cluster (Fargate) – microservice host
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${local.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.prefix}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# IAM role assumed by ECS task execution (pull images, write logs).
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM roles assumed by ECS application tasks (per microservice).
resource "aws_iam_role" "ecs_task" {
  for_each = toset(local.microservices)

  name = "${local.prefix}-${each.key}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Relational Databases (Aurora PostgreSQL for account and payment services)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${local.prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${local.prefix}-db-subnet-group" }
}

resource "aws_rds_cluster" "account" {
  cluster_identifier      = "${local.prefix}-account-aurora"
  engine                  = "aurora-postgresql"
  engine_version         = var.db_engine_version
  database_name          = "account"
  master_username        = var.db_username
  master_password        = var.db_password
  storage_encrypted      = true
  kms_key_id             = var.enable_kms_customer_managed_keys ? aws_kms_key.transaction_data[0].arn : null
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.private_data.id]
  skip_final_snapshot    = var.environment != "prod"
  deletion_protection    = var.environment == "prod"

  tags = { Name = "${local.prefix}-account-aurora" }
}

resource "aws_rds_cluster_instance" "account" {
  identifier         = "${local.prefix}-account-aurora-1"
  cluster_identifier = aws_rds_cluster.account.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.account.engine
  engine_version     = aws_rds_cluster.account.engine_version
  publicly_accessible = false

  tags = { Name = "${local.prefix}-account-aurora-1" }
}

resource "aws_rds_cluster" "payment" {
  cluster_identifier      = "${local.prefix}-payment-aurora"
  engine                  = "aurora-postgresql"
  engine_version          = var.db_engine_version
  database_name           = "payment"
  master_username         = var.db_username
  master_password         = var.db_password
  storage_encrypted       = true
  kms_key_id              = var.enable_kms_customer_managed_keys ? aws_kms_key.transaction_data[0].arn : null
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.private_data.id]
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"

  tags = { Name = "${local.prefix}-payment-aurora" }
}

resource "aws_rds_cluster_instance" "payment" {
  identifier          = "${local.prefix}-payment-aurora-1"
  cluster_identifier  = aws_rds_cluster.payment.id
  instance_class      = var.db_instance_class
  engine              = aws_rds_cluster.payment.engine
  engine_version      = aws_rds_cluster.payment.engine_version
  publicly_accessible = false

  tags = { Name = "${local.prefix}-payment-aurora-1" }
}

# ─────────────────────────────────────────────────────────────────────────────
# ElastiCache (Redis) – session store / caching layer
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.prefix}-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.prefix}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = var.redis_engine_version
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.private_data.id]

  tags = { Name = "${local.prefix}-redis" }
}

# ─────────────────────────────────────────────────────────────────────────────
# SQS Queues – async messaging between microservices
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "transactions_dlq" {
  name                      = "${local.prefix}-transactions-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
  tags                      = { Name = "${local.prefix}-transactions-dlq" }
}

resource "aws_sqs_queue" "transactions" {
  name                       = "${local.prefix}-transactions"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400 # 1 day
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.transactions_dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Name = "${local.prefix}-transactions" }
}

resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "${local.prefix}-notifications-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = { Name = "${local.prefix}-notifications-dlq" }
}

resource "aws_sqs_queue" "notifications" {
  name                       = "${local.prefix}-notifications"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notifications_dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Name = "${local.prefix}-notifications" }
}

resource "aws_sqs_queue" "manual_review_dlq" {
  name                      = "${local.prefix}-manual-review-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = { Name = "${local.prefix}-manual-review-dlq" }
}

resource "aws_sqs_queue" "manual_review" {
  name                       = "${local.prefix}-manual-review"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.manual_review_dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Name = "${local.prefix}-manual-review" }
}

resource "aws_sqs_queue_policy" "transactions" {
  queue_url = aws_sqs_queue.transactions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPaymentServiceSend"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_task["payment"].arn
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.transactions.arn
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.transactions.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "notifications" {
  queue_url = aws_sqs_queue.notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPaymentServiceSend"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_task["payment"].arn
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.notifications.arn
      },
      {
        Sid    = "AllowNotificationServiceConsume"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ecs_task["notification"].arn
        }
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.notifications.arn
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.notifications.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "manual_review" {
  queue_url = aws_sqs_queue.manual_review.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStepFunctionsSend"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.step_functions.arn
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.manual_review.arn
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.manual_review.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 – static frontend assets
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.prefix}-frontend-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${local.prefix}-frontend" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudFront – CDN for the frontend
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.prefix}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  # SPA fallback – serve index.html for unknown paths
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # TODO: Replace with acm_certificate_arn once a custom domain is set up.
  }

  tags = { Name = "${local.prefix}-cloudfront" }
}

# S3 bucket policy – allow CloudFront OAC to read objects
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# API Gateway (HTTP API) – entry point for backend microservices
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${aws_cloudfront_distribution.frontend.domain_name}"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = { Name = "${local.prefix}-api" }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  tags = { Name = "${local.prefix}-api-stage" }
}

resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id                            = aws_apigatewayv2_api.main.id
  authorizer_type                   = "JWT"
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "${local.prefix}-cognito-jwt"
  authorizer_payload_format_version = "2.0"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.web.id]
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

# API Gateway private integration to ECS microservices over VPC Link.
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${local.prefix}-api-vpc-link"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.private_app.id]

  tags = { Name = "${local.prefix}-api-vpc-link" }
}

resource "aws_apigatewayv2_integration" "microservice" {
  for_each = toset(local.microservices)

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id
  integration_uri = var.use_localstack ? null : aws_service_discovery_service.microservice[each.key].arn

  timeout_milliseconds = 30000
  description          = "Private proxy integration to ${each.key} service via Cloud Map."

  # Ensure each service is running and registered before API integration is created.
  depends_on = [aws_ecs_service.microservice]
}

resource "aws_apigatewayv2_route" "microservice" {
  for_each = local.microservice_api_routes
  

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.microservice[each.value.service].id}"
  authorization_type = var.use_localstack ? "NONE" : "JWT"
  authorizer_id      = var.use_localstack ? null : aws_apigatewayv2_authorizer.cognito_jwt.id
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch Log Group – centralised application logging
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/sbcbank/${var.environment}/app"
  retention_in_days = 30
  kms_key_id        = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
  tags              = { Name = "${local.prefix}-log-group" }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.prefix}/flow-logs"
  retention_in_days = 30
  kms_key_id        = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
  tags              = { Name = "${local.prefix}-vpc-flow-logs" }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${local.prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${local.prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ]
      Resource = [
        "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      ]
    }]
  })
}

resource "aws_flow_log" "vpc" {
  iam_role_arn         = aws_iam_role.vpc_flow_logs.arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Cognito – authentication/user management
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cognito_user_pool" "main" {
  name = "${local.prefix}-${var.cognito_user_pool_name}"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  tags = { Name = "${local.prefix}-cognito-user-pool" }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  explicit_auth_flows                  = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = false
}

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.prefix}-${var.cognito_identity_pool_name}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.web.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Lambda – async functions scaffold
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_execution" {
  for_each = local.lambda_sources

  name = "${local.prefix}-${each.key}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  for_each = aws_iam_role.lambda_execution

  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_notification_data_access" {
  name = "${local.prefix}-notification-lambda-data-policy"
  role = aws_iam_role.lambda_execution["notification"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject"
      ]
      Resource = [
        "${aws_s3_bucket.statements.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "lambda_fraud_data_access" {
  name = "${local.prefix}-fraud-lambda-data-policy"
  role = aws_iam_role.lambda_execution["fraud"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem"
      ]
      Resource = [
        "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.prefix}-fraud-events"
      ]
    }]
  })
}

data "archive_file" "lambda_package" {
  for_each    = local.lambda_sources
  type        = "zip"
  source_file = each.value
  output_path = "${path.module}/../lambdas/${each.key}_lambda.zip"
}

resource "aws_s3_object" "lambda_package" {
  for_each = data.archive_file.lambda_package

  bucket = aws_s3_bucket.lambda_artifacts.id
  key    = "lambda/${each.key}.zip"
  source = each.value.output_path
  etag   = filemd5(each.value.output_path)
}

resource "aws_lambda_function" "notification" {
  function_name = "${local.prefix}-notification-lambda"
  role          = aws_iam_role.lambda_execution["notification"].arn
  runtime       = var.lambda_runtime
  handler       = var.notification_lambda_handler

  s3_bucket        = aws_s3_bucket.lambda_artifacts.id
  s3_key           = aws_s3_object.lambda_package["notification"].key
  source_code_hash = data.archive_file.lambda_package["notification"].output_base64sha256

  tags = { Name = "${local.prefix}-notification-lambda" }
}

resource "aws_lambda_function" "fraud" {
  function_name = "${local.prefix}-fraud-lambda"
  role          = aws_iam_role.lambda_execution["fraud"].arn
  runtime       = var.lambda_runtime
  handler       = var.fraud_lambda_handler

  s3_bucket        = aws_s3_bucket.lambda_artifacts.id
  s3_key           = aws_s3_object.lambda_package["fraud"].key
  source_code_hash = data.archive_file.lambda_package["fraud"].output_base64sha256

  tags = { Name = "${local.prefix}-fraud-lambda" }
}

resource "aws_lambda_function" "default_bus_probe" {
  function_name = "${local.prefix}-default-bus-probe-lambda"
  role          = aws_iam_role.lambda_execution["default_bus_probe"].arn
  runtime       = var.lambda_runtime
  handler       = "default_bus_probe_lambda.handler"

  s3_bucket        = aws_s3_bucket.lambda_artifacts.id
  s3_key           = aws_s3_object.lambda_package["default_bus_probe"].key
  source_code_hash = data.archive_file.lambda_package["default_bus_probe"].output_base64sha256

  tags = { Name = "${local.prefix}-default-bus-probe-lambda" }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step Functions – payment orchestration workflow
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "step_functions" {
  name = "${local.prefix}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "step_functions" {
  name = "${local.prefix}-step-functions-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.fraud.arn,
          "${aws_lambda_function.fraud.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = [
          aws_cloudwatch_event_bus.main.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.manual_review.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "payment_workflow" {
  name              = "/aws/states/${local.prefix}-payment-workflow"
  retention_in_days = 30
  kms_key_id        = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
  tags              = { Name = "${local.prefix}-payment-workflow-logs" }
}

resource "aws_sfn_state_machine" "payment_workflow" {
  name     = "${local.prefix}-payment-workflow"
  role_arn = aws_iam_role.step_functions.arn

  # Avoid IAM propagation race by ensuring policy attachment exists first.
  depends_on = [aws_iam_role_policy.step_functions]

  logging_configuration {
    include_execution_data = true
    level                  = "ALL"

    log_destination = "${aws_cloudwatch_log_group.payment_workflow.arn}:*"
  }

  definition = jsonencode({
    Comment = "SBCbank payment orchestration workflow"
    StartAt = "ValidateAccounts"
    States = {
      ValidateAccounts = {
        Type = "Pass"
        Parameters = {
          "validated.$" = "$.payment"
        }
        Next = "CreatePendingTransaction"
      }
      CreatePendingTransaction = {
        Type = "Pass"
        Parameters = {
          "payment.$"       = "$.validated"
          transactionStatus = "PENDING"
        }
        Next = "PublishPaymentInitiated"
      }
      PublishPaymentInitiated = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:events:putEvents"
        Parameters = {
          Entries = [
            {
              Source       = "sbcbank.transactions"
              DetailType   = "PaymentInitiated"
              EventBusName = aws_cloudwatch_event_bus.main.name
              "Detail.$"   = "States.JsonToString($.payment)"
            }
          ]
        }
        ResultPath = "$.eventResult"
        Next       = "FraudCheck"
      }
      FraudCheck = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.fraud.arn
          Payload = {
            "detail.$" = "$.payment"
          }
        }
        ResultSelector = {
          "decision.$"    = "States.StringToJson($.Payload.body).decision"
          "riskScore.$"   = "States.StringToJson($.Payload.body).riskScore"
          "evaluatedAt.$" = "States.StringToJson($.Payload.body).evaluatedAt"
        }
        ResultPath = "$.fraud"
        Next       = "FraudDecision"
      }
      FraudDecision = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.fraud.decision"
            StringEquals = "APPROVE"
            Next         = "ApproveTransaction"
          },
          {
            Variable     = "$.fraud.decision"
            StringEquals = "FLAG"
            Next         = "SendToManualReviewQueue"
          },
          {
            Variable     = "$.fraud.decision"
            StringEquals = "MANUAL_REVIEW"
            Next         = "SendToManualReviewQueue"
          },
          {
            Variable     = "$.fraud.decision"
            StringEquals = "BLOCK"
            Next         = "BlockTransaction"
          }
        ]
        Default = "BlockTransaction"
      }
      ApproveTransaction = {
        Type = "Pass"
        Parameters = {
          "payment.$" = "$.payment"
          status      = "SUCCESS"
        }
        Next = "PublishPaymentCompleted"
      }
      PublishPaymentCompleted = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:events:putEvents"
        Parameters = {
          Entries = [
            {
              Source       = "sbcbank.transactions"
              DetailType   = "PaymentCompleted"
              EventBusName = aws_cloudwatch_event_bus.main.name
              "Detail.$"   = "States.JsonToString($.payment)"
            }
          ]
        }
        ResultPath = "$.eventResult"
        End        = true
      }
      SendToManualReviewQueue = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:sqs:sendMessage"
        Parameters = {
          QueueUrl        = aws_sqs_queue.manual_review.url
          "MessageBody.$" = "States.JsonToString($)"
        }
        ResultPath = "$.manualReviewResult"
        Next       = "PublishFraudFlagged"
      }
      PublishFraudFlagged = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:events:putEvents"
        Parameters = {
          Entries = [
            {
              Source       = "sbcbank.fraud"
              DetailType   = "FraudFlagged"
              EventBusName = aws_cloudwatch_event_bus.main.name
              "Detail.$"   = "States.JsonToString($)"
            }
          ]
        }
        ResultPath = "$.eventResult"
        End        = true
      }
      BlockTransaction = {
        Type = "Pass"
        Parameters = {
          "payment.$" = "$.payment"
          status      = "FAILED"
          reason      = "FRAUD_BLOCKED"
        }
        Next = "PublishPaymentFailed"
      }
      PublishPaymentFailed = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:events:putEvents"
        Parameters = {
          Entries = [
            {
              Source       = "sbcbank.transactions"
              DetailType   = "PaymentFailed"
              EventBusName = aws_cloudwatch_event_bus.main.name
              "Detail.$"   = "States.JsonToString($)"
            }
          ]
        }
        ResultPath = "$.eventResult"
        End        = true
      }
    }
  })

  tags = { Name = "${local.prefix}-payment-workflow" }
}

resource "aws_lambda_permission" "allow_stepfunctions_fraud" {
  statement_id  = "AllowStepFunctionsInvokeFraudLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fraud.function_name
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.payment_workflow.arn
}

# ─────────────────────────────────────────────────────────────────────────────
# EventBridge – integration event bus + rules
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_bus" "main" {
  name = "${local.prefix}-${var.eventbridge_bus_name}"
  tags = { Name = "${local.prefix}-event-bus" }
}

resource "aws_cloudwatch_event_rule" "notifications" {
  name           = "${local.prefix}-notifications-rule"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  event_pattern = jsonencode({
    source        = ["sbcbank.transactions", "sbcbank.fraud"]
    "detail-type" = ["PaymentCompleted", "PaymentFailed", "FraudFlagged"]
  })
}

resource "aws_cloudwatch_event_target" "notifications_lambda" {
  rule           = aws_cloudwatch_event_rule.notifications.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "notify-lambda"
  arn            = aws_lambda_function.notification.arn
}

resource "aws_lambda_permission" "allow_eventbridge_notification" {
  statement_id  = "AllowEventBridgeInvokeNotificationLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.notifications.arn
}

# Temporary diagnostics rule: captures all events put on the default bus so we
# can identify unexpected producers still using default instead of custom bus.
resource "aws_cloudwatch_event_rule" "default_bus_diagnostics" {
  count          = var.use_localstack ? 0 : 1
  name           = "${local.prefix}-default-bus-diagnostics"
  event_bus_name = "default"
  event_pattern = jsonencode({
  source = [{ "prefix" = "" }]
})
}

resource "aws_cloudwatch_event_target" "default_bus_diagnostics_lambda" {
  count          = var.use_localstack ? 0 : 1
  rule           = aws_cloudwatch_event_rule.default_bus_diagnostics[count.index].name
  event_bus_name = aws_cloudwatch_event_rule.default_bus_diagnostics[count.index].event_bus_name
  target_id      = "default-bus-probe-lambda"
  arn            = aws_lambda_function.default_bus_probe.arn
}

resource "aws_lambda_permission" "allow_eventbridge_default_bus_diagnostics" {
  count         = var.use_localstack ? 0 : 1
  statement_id  = "AllowEventBridgeInvokeDefaultBusProbeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.default_bus_probe.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.default_bus_diagnostics[count.index].arn
}

# ─────────────────────────────────────────────────────────────────────────────
# Fraud Detector – scaffold placeholder
# ─────────────────────────────────────────────────────────────────────────────

# NOTE: hashicorp/aws does not currently expose Fraud Detector resources.
# This placeholder keeps intent explicit until provider support is available
# or an alternate implementation path (SDK/custom module) is chosen.
resource "terraform_data" "fraud_detector_stub" {
  input = {
    detector_id = "${local.prefix}-${var.fraud_detector_id}"
    service     = "frauddetector"
    status      = "stub"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS microservices – task definition + service scaffolding
# ─────────────────────────────────────────────────────────────────────────────

locals {
  microservices = [
    "user",
    "account",
    "payment",
    "ledger",
    "statement",
    "notification"
  ]

  microservice_api_prefixes = {
    user         = "/users"
    account      = "/accounts"
    payment      = "/payments"
    ledger       = "/ledgers"
    statement    = "/statements"
    notification = "/notifications"
  }

  microservice_api_routes = merge(
    {
      for service, prefix in local.microservice_api_prefixes :
      "${service}_root" => {
        service   = service
        route_key = "ANY ${prefix}"
      }
    },
    {
      for service, prefix in local.microservice_api_prefixes :
      "${service}_proxy" => {
        service   = service
        route_key = "ANY ${prefix}/{proxy+}"
      }
    }
  )

  # Service-level task permissions keep runtime access scoped by microservice.
  ecs_service_role_policies = {
    account = [
      {
        Sid    = "AccountServiceQueueWrite"
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [
          aws_sqs_queue.transactions.arn
        ]
      }
    ]
    payment = [
      {
        Sid    = "PaymentServiceQueueWrite"
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [
          aws_sqs_queue.transactions.arn,
          aws_sqs_queue.notifications.arn
        ]
      },
      {
        Sid    = "PaymentServiceEventPublish"
        Effect = "Allow"
        Action = ["events:PutEvents"]
        Resource = [
          aws_cloudwatch_event_bus.main.arn
        ]
      }
    ]
    ledger = [
      {
        Sid    = "LedgerServiceTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.prefix}-ledger"
        ]
      }
    ]
    statement = [
      {
        Sid    = "StatementServiceTableRead"
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.prefix}-ledger"
        ]
      },
      {
        Sid    = "StatementServiceS3Read"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${aws_s3_bucket.statements.arn}/*"
        ]
      }
    ]
    notification = [
      {
        Sid    = "NotificationServiceQueueConsume"
        Effect = "Allow"
        Action = [
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage"
        ]
        Resource = [
          aws_sqs_queue.notifications.arn
        ]
      }
    ]
  }
}

resource "aws_service_discovery_private_dns_namespace" "microservices" {
  count = var.use_localstack ? 0 : 1
  name  = "${local.prefix}.internal"
  vpc   = aws_vpc.main.id
  tags  = { Name = "${local.prefix}-microservices-namespace" }
}

resource "aws_service_discovery_service" "microservice" {
   for_each = var.use_localstack ? toset([]) : toset(local.microservices)  

  name = each.key

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.microservices[0].id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "SRV"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = { Name = "${local.prefix}-${each.key}-discovery" }
}

resource "aws_iam_role_policy" "ecs_task_app_permissions" {
  for_each = local.ecs_service_role_policies

  name = "${local.prefix}-${each.key}-ecs-task-app-policy"
  role = aws_iam_role.ecs_task[each.key].id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value
  })
}

resource "aws_ecs_task_definition" "microservice" {
  for_each = toset(local.microservices)

  family                   = "${local.prefix}-${each.key}-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  # TODO: Replace demo image and env vars with real service containers.
  container_definitions = jsonencode([
    {
      name      = "${each.key}-service"
      image     = "public.ecr.aws/docker/library/nginx:stable-alpine"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = each.key
        }
      }
    }
  ])

  tags = { Name = "${local.prefix}-${each.key}-taskdef" }
}

resource "aws_ecs_service" "microservice" {
  for_each = toset(local.microservices)

  name            = "${local.prefix}-${each.key}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.microservice[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.private_app.id]
    assign_public_ip = false
  }

  dynamic "service_registries" {
  for_each = var.use_localstack ? [] : [1]
  content {
    registry_arn   = aws_service_discovery_service.microservice[each.key].arn
    container_name = "${each.key}-service"
    container_port = 80
  }
}

  # Ensure ECS capacity provider attachment is in place before service creation.
  depends_on = [aws_ecs_cluster_capacity_providers.main]

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Name = "${local.prefix}-${each.key}-ecs-service" }
}

# ─────────────────────────────────────────────────────────────────────────────
# Additional S3 bucket – business data (statements/documents)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "statements" {
  bucket = "${local.prefix}-statements-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${local.prefix}-statements" }
}

resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "${local.prefix}-lambda-artifacts-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${local.prefix}-lambda-artifacts" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_customer_managed_keys ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_customer_managed_keys ? aws_kms_key.transaction_data[0].arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_artifacts" {
  bucket                  = aws_s3_bucket.lambda_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "statements" {
  bucket = aws_s3_bucket.statements.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_customer_managed_keys ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_customer_managed_keys ? aws_kms_key.pii_data[0].arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "statements" {
  bucket                  = aws_s3_bucket.statements.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "statements" {
  bucket = aws_s3_bucket.statements.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "statements" {
  bucket = aws_s3_bucket.statements.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.statements.arn,
        "${aws_s3_bucket.statements.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudTrail – account-level audit logging
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${local.prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${local.prefix}-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_customer_managed_keys ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${local.prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  kms_key_id                    = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = { Name = "${local.prefix}-trail" }
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch Alarms – baseline operational alerts
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.prefix}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alarm when API Gateway returns too many 5xx responses"

  dimensions = {
    ApiId = aws_apigatewayv2_api.main.id
    Stage = aws_apigatewayv2_stage.default.name
  }
}

resource "aws_cloudwatch_metric_alarm" "aurora_account_cpu_high" {
  alarm_name          = "${local.prefix}-aurora-account-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when Aurora account writer CPU utilization is persistently high"

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.account.id
  }
}

resource "aws_cloudwatch_metric_alarm" "aurora_payment_cpu_high" {
  alarm_name          = "${local.prefix}-aurora-payment-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when Aurora payment writer CPU utilization is persistently high"

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.payment.id
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Compliance analytics – Athena + Glue + CloudWatch dashboard/alarms
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.prefix}-athena-results-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${local.prefix}-athena-results" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_customer_managed_keys ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "compliance_metrics_data" {
  bucket = "${local.prefix}-compliance-metrics-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${local.prefix}-compliance-metrics" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "compliance_metrics_data" {
  bucket = aws_s3_bucket.compliance_metrics_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_customer_managed_keys ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "compliance_metrics_data" {
  bucket                  = aws_s3_bucket.compliance_metrics_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "compliance_metrics_data" {
  bucket = aws_s3_bucket.compliance_metrics_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_glue_catalog_database" "compliance" {
  name = "${var.compliance_glue_database_name}_${var.environment}"
}

resource "aws_glue_catalog_table" "compliance_snapshots" {
  name          = var.compliance_glue_table_name
  database_name = aws_glue_catalog_database.compliance.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
    typeOfData     = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.compliance_metrics_data.bucket}/snapshots/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "snapshot_time"
      type = "string"
    }

    columns {
      name = "payment_success_rate_pct_30d"
      type = "double"
    }

    columns {
      name = "failed_payments_30d"
      type = "bigint"
    }

    columns {
      name = "failed_workflows_30d"
      type = "bigint"
    }

    columns {
      name = "running_workflows_30d"
      type = "bigint"
    }

    columns {
      name = "high_value_payments_30d"
      type = "bigint"
    }

    columns {
      name = "avg_payment_amount_30d"
      type = "double"
    }

    columns {
      name = "ledger_coverage_pct"
      type = "double"
    }

    columns {
      name = "statement_coverage_pct"
      type = "double"
    }
  }
}

resource "aws_athena_workgroup" "compliance" {
  name = "${local.prefix}-compliance"

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"
    }
  }

  state = "ENABLED"
  tags  = { Name = "${local.prefix}-athena-compliance" }
}

resource "aws_athena_named_query" "latest_compliance_snapshot" {
  name      = "${local.prefix}-latest-compliance-snapshot"
  database  = aws_glue_catalog_database.compliance.name
  workgroup = aws_athena_workgroup.compliance.name

  query = <<-SQL
    SELECT
      from_iso8601_timestamp(snapshot_time) AS snapshot_time,
      payment_success_rate_pct_30d,
      failed_payments_30d,
      failed_workflows_30d,
      running_workflows_30d,
      high_value_payments_30d,
      avg_payment_amount_30d,
      ledger_coverage_pct,
      statement_coverage_pct
    FROM ${var.compliance_glue_table_name}
    ORDER BY from_iso8601_timestamp(snapshot_time) DESC
    LIMIT 1;
  SQL
}

resource "aws_cloudwatch_log_group" "compliance_metrics" {
  name              = "/sbcbank/${var.environment}/compliance-metrics"
  retention_in_days = 30
  kms_key_id        = var.enable_kms_customer_managed_keys ? aws_kms_key.logs[0].arn : null
  tags              = { Name = "${local.prefix}-compliance-metrics-log-group" }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM governance – human access roles, identity center, SCPs, and KMS CMKs
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "human_access" {
  for_each = var.enable_human_iam_roles ? local.human_access_roles : {}

  name                 = "${local.prefix}-${each.key}-role"
  description          = each.value.description
  max_session_duration = 14400

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = local.human_role_assume_principals
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "human_access_managed" {
  for_each = var.enable_human_iam_roles ? local.human_access_role_policy_attachments : {}

  role       = aws_iam_role.human_access[each.value.role_name].name
  policy_arn = each.value.policy_arn
}

resource "aws_kms_key" "transaction_data" {
  count = var.enable_kms_customer_managed_keys ? 1 : 0

  description             = "${local.prefix} transaction data CMK"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowTransactionWorkloads"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.ecs_task["account"].arn,
            aws_iam_role.ecs_task["payment"].arn,
            aws_iam_role.ecs_task["ledger"].arn,
            aws_iam_role.step_functions.arn,
            aws_iam_role.lambda_execution["fraud"].arn
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${local.prefix}-transaction-data-key" }
}

resource "aws_kms_alias" "transaction_data" {
  count = var.enable_kms_customer_managed_keys ? 1 : 0

  name          = "alias/${local.prefix}-transaction-data"
  target_key_id = aws_kms_key.transaction_data[0].key_id
}

resource "aws_kms_key" "pii_data" {
  count = var.enable_kms_customer_managed_keys ? 1 : 0

  description             = "${local.prefix} PII data CMK"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowPIIWorkloads"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.ecs_task["account"].arn,
            aws_iam_role.ecs_task["statement"].arn,
            aws_iam_role.lambda_execution["notification"].arn
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${local.prefix}-pii-data-key" }
}

resource "aws_kms_alias" "pii_data" {
  count = var.enable_kms_customer_managed_keys ? 1 : 0

  name          = "alias/${local.prefix}-pii-data"
  target_key_id = aws_kms_key.pii_data[0].key_id
}

resource "aws_kms_key" "logs" {
  count = var.enable_kms_customer_managed_keys ? 1 : 0

  description             = "${local.prefix} logs and audit CMK"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudTrailUse"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsUse"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowFlowLogsAndWorkflowRoles"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.vpc_flow_logs.arn,
            aws_iam_role.step_functions.arn
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${local.prefix}-logs-key" }
}

resource "aws_kms_alias" "logs" {
  count = var.enable_kms_customer_managed_keys ? 1 : 0

  name          = "alias/${local.prefix}-logs"
  target_key_id = aws_kms_key.logs[0].key_id
}

resource "aws_ssoadmin_permission_set" "human_access" {
  for_each = local.identity_center_enabled ? local.identity_center_permission_sets : {}

  instance_arn     = var.identity_center_instance_arn
  name             = "${local.prefix}-${each.key}"
  description      = each.value.description
  session_duration = each.value.session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "human_access" {
  for_each = local.identity_center_enabled ? local.identity_center_permission_set_policy_attachments : {}

  instance_arn       = var.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.human_access[each.value.permission_set_name].arn
  managed_policy_arn = each.value.policy_arn
}

resource "aws_organizations_policy" "deny_root_user_actions" {
  count = local.organizations_governance_enabled ? 1 : 0

  name        = "${local.prefix}-deny-root-user-actions"
  description = "Deny API access when principal is root user"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyRootUserActions"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy" "restrict_non_singapore_regions" {
  count = local.organizations_governance_enabled ? 1 : 0

  name        = "${local.prefix}-restrict-non-singapore-regions"
  description = "Restrict operations to ap-southeast-1 except global services"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnsupportedRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "cloudfront:*",
          "support:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = "ap-southeast-1"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy" "enforce_encryption" {
  count = local.organizations_governance_enabled ? 1 : 0

  name        = "${local.prefix}-enforce-encryption"
  description = "Enforce encryption at rest and secure transport"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyUnencryptedS3Puts"
        Effect   = "Deny"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::*/*"
        Condition = {
          StringNotEqualsIfExists = {
            "s3:x-amz-server-side-encryption" = ["AES256", "aws:kms"]
          }
        }
      },
      {
        Sid      = "DenyInsecureS3Transport"
        Effect   = "Deny"
        Action   = "s3:*"
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_root_user_actions" {
  count = local.organizations_governance_enabled && length(trimspace(var.organizations_scp_target_id)) > 0 ? 1 : 0

  policy_id = aws_organizations_policy.deny_root_user_actions[0].id
  target_id = var.organizations_scp_target_id
}

resource "aws_organizations_policy_attachment" "restrict_non_singapore_regions" {
  count = local.organizations_governance_enabled && length(trimspace(var.organizations_scp_target_id)) > 0 ? 1 : 0

  policy_id = aws_organizations_policy.restrict_non_singapore_regions[0].id
  target_id = var.organizations_scp_target_id
}

resource "aws_organizations_policy_attachment" "enforce_encryption" {
  count = local.organizations_governance_enabled && length(trimspace(var.organizations_scp_target_id)) > 0 ? 1 : 0

  policy_id = aws_organizations_policy.enforce_encryption[0].id
  target_id = var.organizations_scp_target_id
}

resource "aws_cloudwatch_log_metric_filter" "payment_success_rate" {
  name           = "${local.prefix}-payment-success-rate"
  pattern        = "{ $.payment_success_rate_pct_30d = * }"
  log_group_name = aws_cloudwatch_log_group.compliance_metrics.name

  metric_transformation {
    name      = "PaymentSuccessRate30d"
    namespace = var.compliance_metrics_namespace
    value     = "$.payment_success_rate_pct_30d"
    unit      = "Percent"
  }
}

resource "aws_cloudwatch_log_metric_filter" "workflow_failure_rate" {
  name           = "${local.prefix}-workflow-failure-rate"
  pattern        = "{ $.failed_workflows_30d = * && $.total_payments_30d = * }"
  log_group_name = aws_cloudwatch_log_group.compliance_metrics.name

  metric_transformation {
    name      = "FailedWorkflows30d"
    namespace = var.compliance_metrics_namespace
    value     = "$.failed_workflows_30d"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "ledger_coverage" {
  name           = "${local.prefix}-ledger-coverage"
  pattern        = "{ $.ledger_coverage_pct = * }"
  log_group_name = aws_cloudwatch_log_group.compliance_metrics.name

  metric_transformation {
    name      = "LedgerCoveragePct"
    namespace = var.compliance_metrics_namespace
    value     = "$.ledger_coverage_pct"
    unit      = "Percent"
  }
}

resource "aws_cloudwatch_log_metric_filter" "statement_coverage" {
  name           = "${local.prefix}-statement-coverage"
  pattern        = "{ $.statement_coverage_pct = * }"
  log_group_name = aws_cloudwatch_log_group.compliance_metrics.name

  metric_transformation {
    name      = "StatementCoveragePct"
    namespace = var.compliance_metrics_namespace
    value     = "$.statement_coverage_pct"
    unit      = "Percent"
  }
}

resource "aws_cloudwatch_dashboard" "compliance" {
  dashboard_name = "${local.prefix}-compliance-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Compliance KPI Percentages"
          region = var.aws_region
          stat   = "Average"
          period = 300
          view   = "timeSeries"
          metrics = [
            [var.compliance_metrics_namespace, "PaymentSuccessRate30d"],
            [".", "LedgerCoveragePct"],
            [".", "StatementCoveragePct"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Compliance KPI Counts"
          region = var.aws_region
          stat   = "Average"
          period = 300
          view   = "timeSeries"
          metrics = [
            [var.compliance_metrics_namespace, "FailedWorkflows30d"]
          ]
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "compliance_payment_success_low" {
  alarm_name          = "${local.prefix}-compliance-payment-success-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PaymentSuccessRate30d"
  namespace           = var.compliance_metrics_namespace
  period              = 300
  statistic           = "Average"
  threshold           = 97
  alarm_description   = "Alarm when 30d payment success rate drops below 97%."
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "compliance_ledger_coverage_low" {
  alarm_name          = "${local.prefix}-compliance-ledger-coverage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "LedgerCoveragePct"
  namespace           = var.compliance_metrics_namespace
  period              = 300
  statistic           = "Average"
  threshold           = 98
  alarm_description   = "Alarm when ledger coverage for completed workflows drops below 98%."
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "compliance_statement_coverage_low" {
  alarm_name          = "${local.prefix}-compliance-statement-coverage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatementCoveragePct"
  namespace           = var.compliance_metrics_namespace
  period              = 300
  statistic           = "Average"
  threshold           = 95
  alarm_description   = "Alarm when statement coverage for active accounts drops below 95%."
  treat_missing_data  = "notBreaching"
}
