##############################################################################
# main.tf – SBCbank cloud-native infrastructure (starter template)
#
# Resources defined here are intentional stubs / scaffolding.  Service code
# (container images, Lambda packages, etc.) is NOT required at this stage.
# Fill in TODO comments as the project matures.
##############################################################################

locals {
  prefix           = "${var.project_name}-${var.environment}"
  azs              = slice(data.aws_availability_zones.available.names, 0, 2)
  enable_alb_https = length(trimspace(var.alb_domain_name)) > 0
  lambda_sources = {
    notification = "${path.module}/../lambdas/notification_lambda.py"
    fraud        = "${path.module}/../lambdas/fraud_lambda.py"
  }
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

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb-sg"
  description = "Allow inbound HTTPS from the internet to the ALB."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-alb-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.prefix}-ecs-tasks-sg"
  description = "Allow inbound traffic from the ALB to ECS tasks."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-ecs-tasks-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${local.prefix}-rds-sg"
  description = "Allow inbound PostgreSQL from ECS tasks only."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-rds-sg" }
}

resource "aws_security_group" "redis" {
  name        = "${local.prefix}-redis-sg"
  description = "Allow inbound Redis from ECS tasks only."
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-redis-sg" }
}

# ─────────────────────────────────────────────────────────────────────────────
# Application Load Balancer
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${local.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${local.prefix}-alb" }
}

resource "aws_wafv2_web_acl" "alb" {
  name  = "${local.prefix}-alb-web-acl"
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
    metric_name                = "${local.prefix}-alb-web-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.prefix}-alb-web-acl" }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}

resource "aws_lb_target_group" "default" {
  name        = "${local.prefix}-default-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_acm_certificate" "alb" {
  count             = local.enable_alb_https ? 1 : 0
  domain_name       = var.alb_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.prefix}-alb-cert" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.enable_alb_https ? [1] : []
    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.enable_alb_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.default.arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.enable_alb_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.alb[0].arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}

resource "aws_lb_target_group" "microservice" {
  for_each = toset(local.microservices)

  name        = substr("${local.prefix}-${each.key}-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200-399"
  }

  tags = { Name = "${local.prefix}-${each.key}-tg" }
}

resource "aws_lb_listener_rule" "microservice" {
  for_each = local.microservice_route_priorities

  listener_arn = local.enable_alb_https ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = each.value

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.microservice[each.key].arn
  }

  condition {
    path_pattern {
      values = [local.microservice_route_paths[each.key]]
    }
  }
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

# ─────────────────────────────────────────────────────────────────────────────
# Relational Database (RDS PostgreSQL)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${local.prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${local.prefix}-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier             = "${local.prefix}-postgres"
  engine                 = "postgres"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_encrypted      = true
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = var.environment == "prod"
  skip_final_snapshot    = var.environment != "prod"
  deletion_protection    = var.environment == "prod"

  tags = { Name = "${local.prefix}-postgres" }
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
  security_group_ids   = [aws_security_group.redis.id]

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

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch Log Group – centralised application logging
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/sbcbank/${var.environment}/app"
  retention_in_days = 30
  tags              = { Name = "${local.prefix}-log-group" }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.prefix}/flow-logs"
  retention_in_days = 30
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
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
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
  name = "${local.prefix}-lambda-execution-role"

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
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
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
  role          = aws_iam_role.lambda_execution.arn
  runtime       = var.lambda_runtime
  handler       = var.notification_lambda_handler

  s3_bucket        = aws_s3_bucket.lambda_artifacts.id
  s3_key           = aws_s3_object.lambda_package["notification"].key
  source_code_hash = data.archive_file.lambda_package["notification"].output_base64sha256

  tags = { Name = "${local.prefix}-notification-lambda" }
}

resource "aws_lambda_function" "fraud" {
  function_name = "${local.prefix}-fraud-lambda"
  role          = aws_iam_role.lambda_execution.arn
  runtime       = var.lambda_runtime
  handler       = var.fraud_lambda_handler

  s3_bucket        = aws_s3_bucket.lambda_artifacts.id
  s3_key           = aws_s3_object.lambda_package["fraud"].key
  source_code_hash = data.archive_file.lambda_package["fraud"].output_base64sha256

  tags = { Name = "${local.prefix}-fraud-lambda" }
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
  tags              = { Name = "${local.prefix}-payment-workflow-logs" }
}

resource "aws_sfn_state_machine" "payment_workflow" {
  name     = "${local.prefix}-payment-workflow"
  role_arn = aws_iam_role.step_functions.arn

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
          "payment.$" = "$.validated"
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
              "Detail.$"  = "States.JsonToString($.payment)"
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
          "decision.$"   = "States.StringToJson($.Payload.body).decision"
          "riskScore.$"  = "States.StringToJson($.Payload.body).riskScore"
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
              "Detail.$"  = "States.JsonToString($.payment)"
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
          QueueUrl = aws_sqs_queue.manual_review.url
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
              "Detail.$"  = "States.JsonToString($)"
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
              "Detail.$"  = "States.JsonToString($)"
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

resource "aws_cloudwatch_event_bus" "notifications" {
  name = "notifications"
  tags = { Name = "${local.prefix}-notifications-bus" }
}

resource "aws_cloudwatch_event_rule" "notifications" {
  name           = "${local.prefix}-notifications-rule"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  event_pattern = jsonencode({
    source = ["sbcbank.transactions"]
    detail = {
      eventType = ["transaction.created", "transaction.completed"]
    }
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
    "transaction",
    "ledger",
    "statement",
    "notification"
  ]

  microservice_route_paths = {
    user         = "/user/*"
    account      = "/account/*"
    transaction  = "/transaction/*"
    ledger       = "/ledger/*"
    statement    = "/statement/*"
    notification = "/notification/*"
  }

  microservice_route_priorities = {
    user         = 10
    account      = 20
    transaction  = 30
    ledger       = 40
    statement    = 50
    notification = 60
  }
}

resource "aws_ecs_task_definition" "microservice" {
  for_each = toset(local.microservices)

  family                   = "${local.prefix}-${each.key}-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_execution.arn

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
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.microservice[each.key].arn
    container_name   = "${each.key}-service"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener_rule.microservice]

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
      sse_algorithm = "AES256"
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
      sse_algorithm = "AES256"
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
      sse_algorithm = "AES256"
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
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = { Name = "${local.prefix}-trail" }
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch Alarms – baseline operational alerts
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alarm when ALB returns too many 5xx responses"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.prefix}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm when RDS CPU utilization is persistently high"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}
