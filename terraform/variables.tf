# ============================================================================
#  variables.tf — inputs to the Terraform configuration.
#
#  All variables have sensible defaults except `my_public_ip`, which you
#  must supply via terraform.tfvars. The defaults match this project's
#  requirements (us-east-1, t3.medium, etc.).
# ============================================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment tag — dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Used as a name prefix for every resource"
  type        = string
  default     = "deployforge"
}

# ----------------------------------------------------------------------------
#  Network
# ----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the two public subnets, one per AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread subnets across — must match region"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# ----------------------------------------------------------------------------
#  Compute
# ----------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for master and workers. kubeadm needs >=2GB RAM."
  type        = string
  default     = "t3.medium"   # 2 vCPU, 4 GB RAM, ~$0.0416/hr in us-east-1

  validation {
    # Block t2.micro / t3.micro accidentally — they don't have enough memory
    # for kubeadm and you'll get cryptic OOM errors on join.
    condition     = !contains(["t2.micro", "t3.micro", "t2.nano", "t3.nano"], var.instance_type)
    error_message = "Instance type must have at least 2GB RAM. t2.medium or t3.medium recommended."
  }
}

variable "worker_count" {
  description = "Number of worker nodes to create"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 5
    error_message = "Worker count must be between 1 and 5 (cost guardrail)."
  }
}

variable "root_volume_size_gb" {
  description = "EBS root volume size in GB. Container images can fill 20GB fast."
  type        = number
  default     = 30
}

# ----------------------------------------------------------------------------
#  Access
# ----------------------------------------------------------------------------

variable "key_name" {
  description = "Existing EC2 key pair name in AWS (we created deployforge-key earlier)"
  type        = string
  default     = "deployforge-key"
}

variable "my_public_ip" {
  description = "Your laptop's public IP, in CIDR form (e.g. 1.2.3.4/32). Only this IP can SSH."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$", var.my_public_ip))
    error_message = "Must be a single IP in CIDR /32 form, e.g. 183.82.24.206/32."
  }
}

variable "additional_ssh_cidrs" {
  description = "Extra CIDRs allowed to SSH (e.g. office IP). Empty by default."
  type        = list(string)
  default     = []
}
