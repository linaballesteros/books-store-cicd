variable "aws_region" {
  description = "AWS region where the BookStore resources run."
  type        = string
  default     = "us-east-1"
}

locals {
  environment   = terraform.workspace
  name_prefix   = "bookstore-${local.environment}"
  frontend_port = 80
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "bookstore"
      Environment = local.environment
      ManagedBy   = "Terraform"
    }
  }
}
