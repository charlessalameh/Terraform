############################################
# Phase 4 fix — Pod Identity roles for the add-ons
#
# Why: the node group enforces IMDSv2 with hop limit 1, so normal pods cannot
# borrow the node's IAM role. The EBS CSI controller therefore had no AWS
# credentials and never became healthy (add-on stuck in CREATING -> 20 min timeout).
# Fix (AWS best practice): give each add-on its own IAM role via EKS Pod Identity.
############################################
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# EBS CSI driver -> create/attach EBS volumes (MongoDB disk in Phase 5)
resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# CloudWatch agent + Fluent Bit -> send Container Insights metrics and logs
resource "aws_iam_role" "cloudwatch_agent" {
  name               = "${var.project}-cloudwatch-agent"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
