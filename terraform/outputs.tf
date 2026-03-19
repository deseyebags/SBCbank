output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "rds_endpoint" {
  description = "Connection endpoint for the RDS PostgreSQL instance."
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Connection endpoint for the ElastiCache Redis cluster."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  sensitive   = true
}

output "frontend_bucket_name" {
  description = "Name of the S3 bucket used for frontend assets."
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (use as the app URL until a custom domain is set up)."
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "api_gateway_endpoint" {
  description = "Base URL of the HTTP API Gateway."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "transactions_queue_url" {
  description = "URL of the transactions SQS queue."
  value       = aws_sqs_queue.transactions.url
}

output "notifications_queue_url" {
  description = "URL of the notifications SQS queue."
  value       = aws_sqs_queue.notifications.url
}

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for application logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito user pool."
  value       = aws_cognito_user_pool.main.id
}

output "cognito_identity_pool_id" {
  description = "ID of the Cognito identity pool."
  value       = aws_cognito_identity_pool.main.id
}

output "notification_lambda_arn" {
  description = "ARN of the notification Lambda function."
  value       = aws_lambda_function.notification.arn
}

output "fraud_lambda_arn" {
  description = "ARN of the fraud Lambda function."
  value       = aws_lambda_function.fraud.arn
}

output "eventbridge_bus_name" {
  description = "Name of the EventBridge event bus."
  value       = aws_cloudwatch_event_bus.main.name
}

output "fraud_detector_name" {
  description = "Name of the Fraud Detector."
  value       = terraform_data.fraud_detector_stub.input.detector_id
}

output "statements_bucket_name" {
  description = "Name of the S3 bucket for statements and documents."
  value       = aws_s3_bucket.statements.bucket
}

output "ecs_microservice_task_definition_arns" {
  description = "Task definition ARNs for all scaffolded microservices."
  value       = { for service, td in aws_ecs_task_definition.microservice : service => td.arn }
}

output "ecs_microservice_service_names" {
  description = "ECS service names for all scaffolded microservices."
  value       = { for service, svc in aws_ecs_service.microservice : service => svc.name }
}
