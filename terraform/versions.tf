terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state — created manually once (S3 bucket + DynamoDB lock table),
  # see README Step 0. Comment this block out until that bucket exists,
  # or `terraform init` will fail.
  backend "s3" {
    bucket         = "willbelony-cloud-project-tfstate"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "flagship-cloud-project"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
