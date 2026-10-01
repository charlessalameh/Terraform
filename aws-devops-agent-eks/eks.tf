############################################
# Phase 4 — EKS cluster + managed node group + add-ons
# Uses the community module terraform-aws-modules/eks (v21 = AWS provider 6.x)
############################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # API endpoint reachable from your Mac (kubectl). Restrict to your IP via var.api_allowed_cidrs.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.api_allowed_cidrs

  # Gives the identity running Terraform (terraform-deployer) cluster-admin via an EKS access entry
  enable_cluster_creator_admin_permissions = true

  # Extra Kubernetes admins, e.g. the identity you use in the AWS Console.
  # IAM permissions alone don't show pods/nodes in the console: the principal also
  # needs an EKS access entry (Kubernetes RBAC side).
  access_entries = {
    for arn in local.console_admin_arns : replace(arn, "/[^a-zA-Z0-9]/", "-") => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Phase 3 network: public subnets only (no NAT gateway = no $0.05/h NAT cost)
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Managed add-ons (installed and versioned by AWS)
  addons = {
    vpc-cni = {
      before_compute = true # pod networking — must exist before nodes join
      # Enforce Kubernetes NetworkPolicies (needed for the network-block scenario)
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    eks-pod-identity-agent          = { before_compute = true }
    kube-proxy                      = {}
    coredns                         = {}
    # Persistent volumes for MongoDB (Phase 5) — own IAM role via Pod Identity
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
    # Container Insights: metrics + logs to CloudWatch (the agent's eyes)
    amazon-cloudwatch-observability = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.cloudwatch_agent.arn
        service_account = "cloudwatch-agent"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_ARM_64_STANDARD" # Graviton (ARM) = cheaper
      instance_types = [var.node_instance_type]

      min_size     = 1
      max_size     = 3
      desired_size = var.node_count

      # Same label as the Azure lab's user node pool, so the manifests' nodeSelector works unchanged
      labels = {
        "nodepool-type" = "user"
      }

      # Fallback for host-network pods (they can still reach the node role via IMDS).
      # EBS CSI uses its own Pod Identity role (see addon-iam.tf).
      iam_role_additional_policies = {
        cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Default: the account root user (what you use in the console). Override with var.console_admin_arns.
  console_admin_arns = length(var.console_admin_arns) > 0 ? var.console_admin_arns : [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
}
