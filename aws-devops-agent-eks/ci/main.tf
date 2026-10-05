############################################
# GitHub Actions → AWS role for the DevOps Agent lab (apply ONCE from your Mac)
#
#   cd aws-devops-agent-eks/ci && terraform init && terraform apply
#
# - Reuses the GitHub OIDC provider created by ../../bootstrap
# - Trusted ONLY for jobs running in GitHub Environments "aws-lab-plan" / "aws-lab"
#   of charlessalameh/Terraform (not any branch, not PRs)
# - Permissions: what the lab needs, IAM limited to the lab's own role/policy names
############################################
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    bucket       = "tfstate-charles-demo"
    key          = "aws-devops-agent-eks/ci/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-central-1"
  default_tags {
    tags = { Project = "devops-agent-lab", ManagedBy = "terraform", Lab = "aws-devops-agent-eks", Purpose = "ci" }
  }
}

variable "github_repo" {
  type    = string
  default = "charlessalameh/Terraform"
}

variable "environments" {
  description = "GitHub Environments allowed to assume the role"
  type        = list(string)
  default     = ["aws-lab-plan", "aws-lab"]
}

variable "state_bucket" {
  type    = string
  default = "tfstate-charles-demo"
}

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  acct = data.aws_caller_identity.current.account_id
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only jobs that declare one of these environments — branches/PRs without the environment get nothing
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for e in var.environments : "repo:${var.github_repo}:environment:${e}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = "gha-aws-devops-lab"
  description          = "GitHub Actions role for the AWS DevOps Agent EKS lab"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 7200 # EKS create/destroy can take > 1 h
}

data "aws_iam_policy_document" "ci" {
  # Services the lab creates and manages
  statement {
    sid = "LabServices"
    actions = [
      "ec2:*", "eks:*", "kms:*", "logs:*", "cloudwatch:*", "sns:*", "lambda:*",
      "cloudformation:*", "cloudcontrol:*", "aidevops:*",
      "ssm:GetParameter", "ssm:GetParameters", "sts:GetCallerIdentity",
      "resource-explorer-2:*",
    ]
    resources = ["*"]
  }
  # Webhook secret: only the lab's secret
  statement {
    sid       = "LabSecret"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:*:${local.acct}:secret:devops-agent-lab/*"]
  }
  # Terraform state
  statement {
    sid       = "StateBucket"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}", "arn:aws:s3:::${var.state_bucket}/aws-devops-agent-eks/*"]
  }
  # IAM: read anything, write only the lab's own roles/policies
  statement {
    sid       = "IamRead"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    sid = "IamLabRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::${local.acct}:role/devops-agent-lab-*",
      "arn:aws:iam::${local.acct}:role/default-eks-node-group-*",
    ]
  }
  statement {
    sid = "IamLabPolicies"
    actions = [
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = ["arn:aws:iam::${local.acct}:policy/devops-agent-lab-*"]
  }
  statement {
    sid = "IamEksOidcProvider"
    actions = [
      "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider",
    ]
    resources = ["arn:aws:iam::${local.acct}:oidc-provider/oidc.eks.*"]
  }
  statement {
    sid       = "IamServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.acct}:role/aws-service-role/*"]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "lab-permissions"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}

output "ci_role_arn" {
  description = "Put this in the GitHub secret AWS_LAB_ROLE_ARN"
  value       = aws_iam_role.ci.arn
}
