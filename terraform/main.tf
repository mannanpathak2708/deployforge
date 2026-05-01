# ============================================================================
#  DeployForge — main.tf
#  Provider config, Terraform version constraint, and global default tags.
#
#  Why pin versions: a Terraform configuration that worked yesterday can break
#  tomorrow if a provider releases a breaking change. Pinning gives us
#  reproducible builds — exactly what IaC is meant to deliver.
# ============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"   # accepts 5.40.x through 5.99.x; refuses 6.x
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # State backend: starts as a local file (terraform.tfstate). For team or
  # production work you'd switch to an S3 backend with DynamoDB locking.
  # Instructions for that are in TERRAFORM_GUIDE.md.
}

provider "aws" {
  region = var.aws_region

  # default_tags applies these to every resource the provider creates, so you
  # never have to remember to tag individual resources. Cost Explorer will
  # group everything tagged Project=deployforge for accurate billing.
  default_tags {
    tags = {
      Project     = "deployforge"
      ManagedBy   = "terraform"
      Environment = var.environment
      Owner       = "mannan"
    }
  }
}

# Pull the AWS account ID dynamically — keeps the config portable across
# accounts without hardcoding 560205084884 anywhere.
data "aws_caller_identity" "current" {}

# Used by ec2.tf to look up the most recent Ubuntu 22.04 AMI in this region,
# so we never paste a stale AMI ID that's been deprecated.
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
