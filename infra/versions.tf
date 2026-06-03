terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70.0"
    }
  }

  # Remote state in the shared tfstate bucket (us-east-1, versioned).
  # S3-native locking (use_lockfile) — no DynamoDB table required (TF >= 1.10).
  backend "s3" {
    bucket       = "warewise-tfstate-224193574799"
    key          = "agentcore-solution1/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "agentcore-solution1"
      ManagedBy = "terraform"
    }
  }
}
