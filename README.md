# SBCbank

Cloud-native bank web application – SMU IS458 Project (Team 2).

This project is designed for rapid local development and testing using LocalStack, an open-source AWS cloud emulator. No real AWS account is required for local development.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Repository Structure](#repository-structure)
4. [Local Development with LocalStack](#local-development-with-localstack)
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


## Local Development with LocalStack

This project is optimised for local development using LocalStack, which emulates AWS services on your machine. No real AWS account or credentials are required.

### 1. Prerequisites

- [LocalStack](https://github.com/localstack/localstack)
  - Install via Homebrew: `brew install localstack`
  - Install via pip: `pip install localstack`
- [Docker](https://www.docker.com/) (required for LocalStack)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) >= 2.x

### 2. Clone the repository

```bash
git clone https://github.com/deseyebags/SBCbank.git
cd SBCbank
```

### 3. Start LocalStack

```bash
localstack start
# or, if using Docker Compose:
# docker compose up localstack
```

### 4. Set up mock AWS credentials

Set these environment variables in your shell (these are safe for local use):

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=ap-southeast-1
export LOCALSTACK_HOST=localhost
```

```Powershell
$env:AWS_ACCESS_KEY_ID="test"
$env:AWS_SECRET_ACCESS_KEY="test"
$env:AWS_DEFAULT_REGION="ap-southeast-1"
$env:LOCALSTACK_HOST="localhost"
```

### 5. Deploy infrastructure with Terraform

```bash
cd terraform
terraform init
terraform validate
terraform apply -var-file="localstack.tfvars" -var="db_password=localpassword"
```

> **Note:**
> - The `terraform validate` step checks whether the config is valid.
> - The `localstack.tfvars` file configures Terraform to use LocalStack endpoints and disables the remote backend.
> - All resources are created locally and are accessible via LocalStack at `localhost:4566`.
> - Not all AWS services are fully emulated, but core services (VPC, S3, SQS, RDS, ECS, etc.) are supported.

### 6. Accessing LocalStack Resources

- S3: http://localhost:4566
- SQS: http://localhost:4566/000000000000/queue-name
- RDS: Use the endpoint output by Terraform (may require additional configuration)

See the [LocalStack documentation](https://docs.localstack.cloud/) for more details.

---


## Deploying with Terraform (Cloud Option)

If you wish to deploy to real AWS, uncomment the backend block in `terraform/providers.tf` and provide real AWS credentials. This is not required for local development.

---


## Tearing Down

To remove all local resources:

```bash
cd terraform
terraform destroy -var-file=localstack.tfvars -var="db_password=localpassword"
```

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
| `AWS_ACCESS_KEY_ID` | AWS access key (use `test` for LocalStack) | `test` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key (use `test` for LocalStack) | `test` |
| `AWS_DEFAULT_REGION` | AWS region (CLI default) | `ap-southeast-1` |
