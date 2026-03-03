#!/bin/bash
# setup-localstack.sh
# Automates LocalStack-based SBCbank infrastructure setup
set -e

# 1. Prerequisites check
command -v localstack >/dev/null 2>&1 || { echo >&2 "LocalStack is not installed. Install with 'brew install localstack'"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is not installed. See https://www.docker.com/"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo >&2 "Terraform is not installed. Install with 'brew install terraform'"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo >&2 "AWS CLI is not installed. Install with 'brew install awscli'"; exit 1; }

# 2. Start LocalStack (if not already running)
echo "Starting LocalStack..."
localstack status | grep 'running' >/dev/null 2>&1 || localstack start -d
sleep 5

# 3. Export mock AWS credentials
echo "Setting environment variables for LocalStack..."
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=ap-southeast-1
export LOCALSTACK_HOST=localhost

# 4. Deploy infrastructure with Terraform
cd terraform

echo "Initializing Terraform..."
terraform init

echo "Applying Terraform (LocalStack)..."
terraform apply -auto-approve -var-file=localstack.tfvars -var="db_password=localpassword"

echo "SBCbank infrastructure deployed locally via LocalStack."
echo "Access S3, SQS, etc. at http://localhost:4566."
