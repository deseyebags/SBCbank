# SBCbank

Cloud-native bank web application – SMU IS458 Project (Team 2).

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Repository Structure](#repository-structure)
4. [Environment Setup](#environment-setup)
5. [Deploying with Terraform](#deploying-with-terraform)
6. [Tearing Down](#tearing-down)
7. [Environment Variables Reference](#environment-variables-reference)

---

## Architecture Overview

SBCbank is designed as a set of cloud-native microservices hosted on AWS:

| Layer | Technology |
|---|---|
| Frontend | Single-page app served via **S3 + CloudFront** |
| API Gateway | **AWS API Gateway v2** (HTTP API) |
| Microservices | **Amazon ECS (Fargate)** containers behind an ALB |
| Database | **Amazon RDS PostgreSQL 16** (private subnets) |
| Cache / Sessions | **Amazon ElastiCache Redis 7** |
| Async messaging | **Amazon SQS** (transactions & notifications queues) |
| Logging | **Amazon CloudWatch Logs** |
| Networking | VPC with public + private subnets across 2 AZs, NAT Gateways |

> **Note:** Service code (container images, Lambda packages, etc.) is not required yet. The Terraform template provisions the infrastructure scaffolding so services can be deployed incrementally.

---

## Prerequisites

Install the following tools before working on this project.

| Tool | Minimum version | Installation |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.5.0 | `brew install terraform` / official installer |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | 2.x | `brew install awscli` / official installer |
| [Git](https://git-scm.com/) | 2.x | bundled with most OSes |

You will also need:

- An **AWS account** with permissions to create VPCs, ECS, RDS, S3, CloudFront, API Gateway, SQS, and ElastiCache resources.
- An **IAM user or role** with programmatic access. Store credentials via `aws configure` or environment variables (see below).

---

## Repository Structure

```
SBCbank/
├── terraform/            # Infrastructure-as-Code (Terraform)
│   ├── providers.tf      # AWS provider + remote-state backend
│   ├── variables.tf      # All configurable input variables
│   ├── main.tf           # Core infrastructure resources
│   └── outputs.tf        # Useful output values after apply
└── README.md
```

---

## Environment Setup

### 1. Clone the repository

```bash
git clone https://github.com/deseyebags/SBCbank.git
cd SBCbank
```

### 2. Configure AWS credentials

```bash
aws configure
# AWS Access Key ID:     <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name:   ap-southeast-1
# Default output format: json
```

Alternatively export environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="ap-southeast-1"
```

### 3. (First-time only) Create the Terraform remote-state backend

The `providers.tf` backend block references an S3 bucket and a DynamoDB table.
Create them once before running `terraform init`:

```bash
# Create the state bucket (versioning keeps history of state files)
aws s3api create-bucket \
  --bucket sbcbank-terraform-state \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1

aws s3api put-bucket-versioning \
  --bucket sbcbank-terraform-state \
  --versioning-configuration Status=Enabled

# Create the DynamoDB lock table
aws dynamodb create-table \
  --table-name sbcbank-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1
```

> **Tip:** If you are working locally and don't want a remote backend yet, comment out the `backend "s3" { … }` block in `terraform/providers.tf` and Terraform will use a local `terraform.tfstate` file instead.

---

## Deploying with Terraform

```bash
cd terraform

# Initialise providers and backend
terraform init

# Review what will be created (dry-run)
terraform plan -var="db_password=<CHOOSE_A_STRONG_PASSWORD>"

# Apply the changes
terraform apply -var="db_password=<CHOOSE_A_STRONG_PASSWORD>"
```

You can also store the password in an environment variable to avoid typing it every time:

```bash
export TF_VAR_db_password="<CHOOSE_A_STRONG_PASSWORD>"
terraform apply
```

After a successful apply, Terraform will print the key **output values** (ALB URL, CloudFront domain, API Gateway endpoint, etc.).

### Deploying to a different environment

Use the `environment` variable to target `dev`, `staging`, or `prod`:

```bash
terraform apply \
  -var="environment=staging" \
  -var="db_password=$TF_VAR_db_password"
```

---

## Tearing Down

```bash
cd terraform
terraform destroy -var="db_password=$TF_VAR_db_password"
```

> ⚠️ **`prod` resources** have `deletion_protection = true` and `skip_final_snapshot = false` on RDS to prevent accidental data loss. You must disable these manually before `destroy` will succeed in production.

---

## Environment Variables Reference

| Variable | Description | Default |
|---|---|---|
| `TF_VAR_project_name` | Resource name prefix | `sbcbank` |
| `TF_VAR_environment` | Target environment (`dev`/`staging`/`prod`) | `dev` |
| `TF_VAR_aws_region` | AWS region | `ap-southeast-1` |
| `TF_VAR_vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `TF_VAR_db_instance_class` | RDS instance type | `db.t3.micro` |
| `TF_VAR_db_password` | RDS master password (**required**) | – |
| `TF_VAR_redis_node_type` | ElastiCache node type | `cache.t3.micro` |
| `AWS_ACCESS_KEY_ID` | AWS access key | – |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | – |
| `AWS_DEFAULT_REGION` | AWS region (CLI default) | – |
