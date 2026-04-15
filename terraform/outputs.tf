output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of all private subnets (app and data tiers)."
  value       = concat(aws_subnet.private_app[*].id, aws_subnet.private_data[*].id)
}

output "private_app_subnet_ids" {
  description = "IDs of private application subnets."
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "IDs of private data subnets."
  value       = aws_subnet.private_data[*].id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role used for image pulls and log publishing."
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arns" {
  description = "ARNs of per-microservice ECS task roles."
  value       = { for service, role in aws_iam_role.ecs_task : service => role.arn }
}

output "aurora_account_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster used by account service."
  value       = aws_rds_cluster.account.endpoint
  sensitive   = true
}

output "aurora_payment_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster used by payment service."
  value       = aws_rds_cluster.payment.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Connection endpoint for the ElastiCache Redis cluster."
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  sensitive   = true
}

output "ledger_dynamodb_table_name" {
  description = "DynamoDB table name used for ledger records."
  value       = aws_dynamodb_table.ledger.name
}

output "fraud_events_dynamodb_table_name" {
  description = "DynamoDB table name used for fraud event records."
  value       = aws_dynamodb_table.fraud_events.name
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

output "manual_review_queue_url" {
  description = "URL of the manual review SQS queue for fraud-flagged payments."
  value       = aws_sqs_queue.manual_review.url
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

output "lambda_execution_role_arns" {
  description = "ARNs of Lambda execution roles keyed by function name."
  value       = { for fn, role in aws_iam_role.lambda_execution : fn => role.arn }
}

output "eventbridge_bus_name" {
  description = "Name of the EventBridge event bus."
  value       = aws_cloudwatch_event_bus.main.name
}

output "payment_workflow_state_machine_arn" {
  description = "ARN of the Step Functions payment workflow state machine."
  value       = aws_sfn_state_machine.payment_workflow.arn
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions execution role."
  value       = aws_iam_role.step_functions.arn
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

output "athena_workgroup_name" {
  description = "Athena workgroup used for compliance analytics queries."
  value       = aws_athena_workgroup.compliance.name
}

output "athena_compliance_database_name" {
  description = "Glue/Athena database name for compliance snapshots."
  value       = aws_glue_catalog_database.compliance.name
}

output "athena_compliance_table_name" {
  description = "Glue/Athena table that stores compliance snapshot records."
  value       = aws_glue_catalog_table.compliance_snapshots.name
}

output "athena_results_bucket_name" {
  description = "S3 bucket used by Athena for query results."
  value       = aws_s3_bucket.athena_results.bucket
}

output "compliance_metrics_bucket_name" {
  description = "S3 bucket where compliance metric snapshots are stored for Athena."
  value       = aws_s3_bucket.compliance_metrics_data.bucket
}

output "compliance_metrics_log_group_name" {
  description = "CloudWatch log group used to ingest compliance metric snapshots."
  value       = aws_cloudwatch_log_group.compliance_metrics.name
}

output "compliance_dashboard_name" {
  description = "CloudWatch dashboard name for compliance KPIs."
  value       = aws_cloudwatch_dashboard.compliance.dashboard_name
}

output "human_iam_role_arns" {
  description = "ARNs of human-access IAM roles (admin, devops, auditor, support)."
  value       = { for name, role in aws_iam_role.human_access : name => role.arn }
}

output "kms_key_arns" {
  description = "Customer-managed KMS key ARNs used for transaction, PII, and logs encryption."
  value = {
    transaction_data_key = try(aws_kms_key.transaction_data[0].arn, null)
    pii_data_key         = try(aws_kms_key.pii_data[0].arn, null)
    logs_key             = try(aws_kms_key.logs[0].arn, null)
  }
}

output "identity_center_permission_set_arns" {
  description = "IAM Identity Center permission set ARNs keyed by role name."
  value       = { for name, ps in aws_ssoadmin_permission_set.human_access : name => ps.arn }
}

output "scp_policy_ids" {
  description = "Organizations SCP policy IDs for governance controls."
  value = {
    deny_root_user_actions         = try(aws_organizations_policy.deny_root_user_actions[0].id, null)
    restrict_non_singapore_regions = try(aws_organizations_policy.restrict_non_singapore_regions[0].id, null)
    enforce_encryption             = try(aws_organizations_policy.enforce_encryption[0].id, null)
  }
}
