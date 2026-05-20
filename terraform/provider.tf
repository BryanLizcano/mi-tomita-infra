terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend S3 — crear bucket manualmente antes del primer apply
  # Descomentar después de crear el bucket:
  # backend "s3" {
  #   bucket = "tomita-tf-state-<account-id>"
  #   key    = "tomita-infra/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "tomita-api"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
