# SBCbank AI Coding Agent Instructions

## Project Overview

Cloud-native digital banking infrastructure for Singapore (SMU IS458 Project Team 2). **This is an infrastructure-first project**: Terraform provisions AWS scaffolding before microservice code exists. The system prioritizes MAS regulatory compliance and AWS best practices. Addtionally, this project is designed to be developed with localstack in mind to simulate AWS functionality without incurring costs or needing real AWS credentials during development.

## Unified Requirements Reference

- **Primary combined spec**: [bankinfo_concrete_overview.yaml](../bankinfo_concrete_overview.yaml)
- **Source infra spec**: [bankinfo_infra.yaml](../bankinfo_infra.yaml)
- **Source dev spec**: [bankinfo_dev.yaml](../bankinfo_dev.yaml)

Use [bankinfo_concrete_overview.yaml](../bankinfo_concrete_overview.yaml) as the single working reference when implementing Terraform and wiring service-level integrations. It combines MAS/security constraints with concrete microservice, Lambda, Step Functions, EventBridge, and SQS workflow requirements.

## Architecture

### Core Stack (Singapore Region Only)

- **Region**: `ap-southeast-1` (hardcoded for MAS compliance)
- **Frontend**: S3 + CloudFront (SPA hosting)
- **API Layer**: AWS API Gateway v2 (HTTP API) → ALB → ECS Fargate microservices
- **Data**: RDS PostgreSQL 16 (multi-AZ in prod), ElastiCache Redis 7
- **Async**: SQS queues for transactions and notifications
- **Logging**: CloudWatch Logs centralized at `/sbcbank/{environment}/app`

### Microservices (planned, not yet implemented)

Three services run on ECS Fargate:`account_service`, `payment_service`, `ledger_service`, `statement_service`. See [bankinfo_concrete_overview.yaml](../bankinfo_concrete_overview.yaml) for full architecture spec.

## Critical Workflows

### Infrastructure Deployment

```bash
# First-time setup: Create remote state backend (S3 + DynamoDB)
aws s3api create-bucket --bucket sbcbank-terraform-state --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
aws s3api put-bucket-versioning --bucket sbcbank-terraform-state --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name sbcbank-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region ap-southeast-1

# Deploy infrastructure
cd terraform
terraform init
export TF_VAR_db_password="<strong-password>"
terraform apply -var="environment=dev"  # or staging/prod
```

### Environment Management

- **Environments**: `dev` (default), `staging`, `prod`
- **Prod protections**: `deletion_protection = true`, `skip_final_snapshot = false` on RDS (see [main.tf](../terraform/main.tf#L304-L305))
- **Multi-AZ**: Only enabled for `prod` environment ([main.tf](../terraform/main.tf#L303))
- **Resource naming**: `{project_name}-{environment}-{resource}` pattern via `local.prefix`

## Project-Specific Conventions

### Terraform Patterns

1. **Resources are intentional stubs**: Comments like `# TODO: Replace with...` indicate scaffolding phase. Don't remove TODOs until actual service code exists.
2. **Sensitive outputs**: RDS and Redis endpoints are marked `sensitive = true` ([outputs.tf](../terraform/outputs.tf#L25-L33))
3. **Security groups follow strict isolation**: ALB → ECS tasks → RDS/Redis chain ([main.tf](../terraform/main.tf#L99-L179))
4. **Backend can be local**: Comment out `backend "s3"` block in [providers.tf](../terraform/providers.tf#L14-L20) for local development

### Compliance & Security

- **Singapore-specific**: MAS TRM, MAS Outsourcing Guidelines, PDPA compliance ([bankinfo.yaml](../bankinfo.yaml#L5-L8))
- **Encryption everywhere**: Storage encryption enabled on RDS, S3 versioning on frontend bucket
- **Network isolation**: Databases in private subnets only, no public access
- **Least privilege**: ECS task execution role uses AWS managed policy ([main.tf](../terraform/main.tf#L258-L269))

### Key Files

- **[bankinfo_concrete_overview.yaml](../bankinfo_concrete_overview.yaml)**: Concrete merged requirements for infra + development implementation
- **[bankinfo_infra.yaml](../bankinfo_infra.yaml)**: Infra/compliance source specification
- **[bankinfo_dev.yaml](../bankinfo_dev.yaml)**: Service/workflow development source specification
- **[terraform/main.tf](../terraform/main.tf)**: All infrastructure resources (515 lines, well-commented sections)
- **[terraform/variables.tf](../terraform/variables.tf)**: Configurable parameters (includes validation for environment values)
- **[README.md](../README.md)**: Detailed setup instructions including AWS CLI configuration

## Concrete Delivery Requirements

- Treat networking, IAM, encryption, data, and observability requirements in [bankinfo_concrete_overview.yaml](../bankinfo_concrete_overview.yaml) as non-optional baseline controls.
- Implement orchestration/eventing to match the payment workflow: Step Functions orchestrates account validation, transaction creation, fraud check, and approve/flag/block branching.
- Ensure EventBridge producers/consumers and SQS manual review queue are provisioned and connected according to the merged spec.
- Keep local development aligned with LocalStack-supported services and mock unsupported capabilities as documented in the merged spec.

## Common Tasks

### Adding a New Microservice

1. Define ECS task definition in [main.tf](../terraform/main.tf) (reference the existing ECS cluster at line 244)
2. Create target group and listener rule for ALB routing
3. Add service-specific security group rules
4. Update [outputs.tf](../terraform/outputs.tf) with service endpoints
5. Update [bankinfo_dev.yaml](../bankinfo_dev.yaml), [bankinfo_infra.yaml](../bankinfo_infra.yaml), and [bankinfo_concrete_overview.yaml](../bankinfo_concrete_overview.yaml) if it changes architectural patterns

### Modifying Infrastructure for Different Environments

Use conditional logic based on `var.environment`:

```hcl
multi_az = var.environment == "prod"  # Pattern from main.tf:L303
```

### Debugging Terraform Issues

- **State lock errors**: Check DynamoDB table `sbcbank-terraform-locks`
- **Backend errors**: Verify S3 bucket exists in `ap-southeast-1` region
- **Validation errors**: Check [variables.tf](../terraform/variables.tf#L11-L14) for allowed values

## Integration Points

- **CloudFront ↔ S3**: OAC (Origin Access Control) configured, not legacy OAI ([main.tf](../terraform/main.tf#L400-L427))
- **API Gateway ↔ ALB**: Integration not yet configured (marked as TODO)
- **ECS ↔ RDS/Redis**: Connection via security group rules, endpoints from Terraform outputs
- **SQS queues**: Dead-letter queues configured with 5 max retries ([main.tf](../terraform/main.tf#L351-L367))

## What NOT to Do

- Never deploy outside `ap-southeast-1` region (MAS compliance requirement)
- Don't disable deletion protection in prod without team approval
- Don't commit `terraform.tfstate` files (use remote backend or add to .gitignore)
- Don't add actual service code to this repo yet (infrastructure-only phase)
- Avoid hardcoding secrets; use `TF_VAR_*` environment variables
