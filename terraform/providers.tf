
# For LocalStack, comment out the backend block below to use local state
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
  }

  # Remote state backend – update bucket/key/region before first init.
  # Comment this block out to use a local state file during local development or with LocalStack.
  # backend "s3" {
  #   bucket         = "sbcbank-terraform-state"
  #   key            = "sbcbank/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   encrypt        = true
  #   dynamodb_table = "sbcbank-terraform-locks"
  # }
}

provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = var.use_localstack

  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null
  endpoints {
    elbv2            = "http://localhost:4566"
    apigatewayv2     = "http://localhost:4566"
    athena           = "http://localhost:4566"
    wafv2            = "http://localhost:4566"
    logs             = "http://localhost:4566"
    apigateway       = "http://localhost:4566"
    cloudwatch       = "http://localhost:4566"
    cloudtrail       = "http://localhost:4566"
    events           = "http://localhost:4566"
    cloudfront       = "http://localhost:4566"
    cognitoidentity  = "http://localhost:4566"
    cognitoidp       = "http://localhost:4566"
    dynamodb         = "http://localhost:4566"
    ec2              = "http://localhost:4566"
    ecs              = "http://localhost:4566"
    elasticache      = "http://localhost:4566"
    es               = "http://localhost:4566"
    glue             = "http://localhost:4566"
    iam              = "http://localhost:4566"
    kinesis          = "http://localhost:4566"
    kms              = "http://localhost:4566"
    lambda           = "http://localhost:4566"
    servicediscovery = "http://localhost:4566"
    rds              = "http://localhost:4566"
    route53          = "http://localhost:4566"
    redshift         = "http://localhost:4566"
    s3               = "http://localhost:4566"
    secretsmanager   = "http://localhost:4566"
    ses              = "http://localhost:4566"
    sns              = "http://localhost:4566"
    sqs              = "http://localhost:4566"
    sfn              = "http://localhost:4566"
    ssm              = "http://localhost:4566"
    sts              = "http://localhost:4566"
    cloudformation   = "http://localhost:4566"
  }

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Global services like CloudFront-scoped WAF must be managed from us-east-1.
provider "aws" {
  alias                       = "global"
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = var.use_localstack

  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null
}
