# AWS OIDC Identity Provider Setup for GitHub Actions
# Security Best Practice: Use OIDC instead of long-lived access keys
# Requires: Terraform 1.0+, AWS Provider 4.0+

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS Region for resources"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub Organization Name"
  type        = string
  default     = "your-org"
}

variable "github_repo" {
  description = "your-repo"
  type        = string
  default     = "CIBT"
}

# 1. Create OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's known thumbprint
  
  tags = {
    Name        = "GitHubActionsOIDC"
    Environment = "Lab"
  }
}

# 2. Create IAM Role for Workload
resource "aws_iam_role" "ci_cd_role" {
  name = "GitHubActions-CI-CD-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Purpose = "CI/CD Federation"
  }
}

# 3. Attach Least Privilege Policy (S3 Read Only for Demo)
resource "aws_iam_role_policy" "ci_cd_policy" {
  name = "CI-CD-S3-Read"
  role = aws_iam_role.ci_cd_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
      
        ]
        Resource = [
          "arn:aws:s3:::${var.github_org}-deployment-bucket",
          "arn:aws:s3:::${var.github_org}-deployment-bucket/*"
        ]
      }
    ]
  })
}

output "role_arn" {
  value = aws_iam_role.ci_cd_role.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
