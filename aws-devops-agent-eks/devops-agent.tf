############################################
# Phase 7 — AWS DevOps Agent
#
#  7a (this file, first apply):
#     IAM roles · Agent Space (+ operator web app) · AWS account association
#     · EKS access entry for the agent · empty Secrets Manager secret
#  7b (manual, console): create the webhook, store its HMAC secret in the secret
#  7c (second apply with TF_VAR_devops_agent_webhook_url): trigger Lambda + SNS subscription
#
# Why 7b is manual: the webhook's HMAC secret is returned exactly once at creation
# and no Terraform/CloudFormation resource exposes it. Doing it by hand keeps the
# secret out of Terraform state and git.
############################################

locals {
  agent_name = var.project # "devops-agent-lab"

  # Trust for both agent roles: the DevOps Agent service, only for Agent Spaces in this account/region
  aidevops_conditions = {
    account = data.aws_caller_identity.current.account_id
    arn     = "arn:aws:aidevops:${var.region}:${data.aws_caller_identity.current.account_id}:agentspace/*"
  }
}

data "aws_iam_policy_document" "aidevops_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.aidevops_conditions.account]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.aidevops_conditions.arn]
    }
  }
}

# --- 1. Monitoring role: what the agent uses to read the account (CloudWatch, EKS, logs, ...)
resource "aws_iam_role" "agent_space" {
  name               = "${local.agent_name}-AgentSpaceRole"
  description        = "Assumed by AWS DevOps Agent to investigate this account"
  assume_role_policy = data.aws_iam_policy_document.aidevops_trust.json
}

resource "aws_iam_role_policy_attachment" "agent_space" {
  role       = aws_iam_role.agent_space.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# The agent creates the Resource Explorer service-linked role on first topology discovery
resource "aws_iam_role_policy" "agent_space_slr" {
  name = "AllowCreateServiceLinkedRoles"
  role = aws_iam_role.agent_space.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:CreateServiceLinkedRole"
      Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
    }]
  })
}

# --- 2. Operator role: backs the DevOps Agent web app (investigation timeline, chat)
resource "aws_iam_role" "operator" {
  name               = "${local.agent_name}-OperatorRole"
  description        = "Operator web app role for the DevOps Agent Space"
  assume_role_policy = data.aws_iam_policy_document.aidevops_trust.json
}

resource "aws_iam_role_policy_attachment" "operator" {
  role       = aws_iam_role.operator.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}

# IAM is eventually consistent; the service checks it can assume the roles at create time
resource "time_sleep" "agent_roles" {
  create_duration = "20s"
  depends_on = [
    aws_iam_role_policy_attachment.agent_space,
    aws_iam_role_policy.agent_space_slr,
    aws_iam_role_policy_attachment.operator,
  ]
}

# --- 3. Agent Space
resource "awscc_devopsagent_agent_space" "this" {
  name        = local.agent_name
  description = "Investigates CloudWatch alarms for EKS cluster ${var.cluster_name} (namespace pets)"

  operator_app = {
    iam = {
      operator_app_role_arn = aws_iam_role.operator.arn
    }
  }

  tags = [
    { key = "Project", value = var.project },
    { key = "Lab", value = "aws-devops-agent-eks" },
    { key = "ManagedBy", value = "terraform" },
  ]

  depends_on = [time_sleep.agent_roles]
}

# --- 4. Let the Agent Space monitor this AWS account (all regions)
resource "awscc_devopsagent_association" "aws_account" {
  agent_space_id = awscc_devopsagent_agent_space.this.agent_space_id
  service_id     = "aws"
  configuration = {
    aws = {
      account_id         = data.aws_caller_identity.current.account_id
      account_type       = "monitor"
      assumable_role_arn = aws_iam_role.agent_space.arn
    }
  }
}

# --- 5. Kubernetes read access for the agent (pods, events, logs, deployments)
# IAM alone isn't enough inside EKS — same lesson as the console "Unauthorized" in Phase 4.
# The agent reaches the cluster through the public endpoint: keep api_allowed_cidrs open.
resource "aws_eks_access_entry" "devops_agent" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.agent_space.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "devops_agent" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.agent_space.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonAIOpsAssistantPolicy" # read-only, built for AI ops agents
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.devops_agent]
}

# --- 6. Container for the webhook HMAC secret (value is put in by hand in step 7b)
resource "aws_secretsmanager_secret" "webhook" {
  name                    = "${local.agent_name}/devops-agent-webhook"
  description             = "HMAC secret of the DevOps Agent webhook (value set manually, never in Terraform)"
  recovery_window_in_days = 0 # lab: allow immediate re-create after destroy
}

# --- 7c. Trigger Lambda: SNS alarm -> signed webhook call (only once the webhook URL is known)
locals {
  trigger_enabled = var.devops_agent_webhook_url != null
}

data "archive_file" "trigger" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/devops_agent_trigger"
  output_path = "${path.module}/.build/devops_agent_trigger.zip"
}

resource "aws_iam_role" "trigger" {
  count = local.trigger_enabled ? 1 : 0
  name  = "${local.agent_name}-trigger-lambda"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "trigger_logs" {
  count      = local.trigger_enabled ? 1 : 0
  role       = aws_iam_role.trigger[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "trigger_secret" {
  count = local.trigger_enabled ? 1 : 0
  name  = "ReadWebhookSecret"
  role  = aws_iam_role.trigger[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = aws_secretsmanager_secret.webhook.arn }]
  })
}

resource "aws_lambda_function" "trigger" {
  count            = local.trigger_enabled ? 1 : 0
  function_name    = "${local.agent_name}-devops-agent-trigger"
  description      = "Forwards CloudWatch ALARM notifications to the AWS DevOps Agent webhook"
  role             = aws_iam_role.trigger[0].arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "index.handler"
  filename         = data.archive_file.trigger.output_path
  source_code_hash = data.archive_file.trigger.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      WEBHOOK_URL      = var.devops_agent_webhook_url
      SECRET_ARN       = aws_secretsmanager_secret.webhook.arn
      EKS_CLUSTER_NAME = var.cluster_name
      APP_NAMESPACE    = local.app_namespace
    }
  }
}

resource "aws_cloudwatch_log_group" "trigger" {
  count             = local.trigger_enabled ? 1 : 0
  name              = "/aws/lambda/${local.agent_name}-devops-agent-trigger"
  retention_in_days = 7
}

resource "aws_lambda_permission" "sns" {
  count         = local.trigger_enabled ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trigger[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "trigger" {
  count     = local.trigger_enabled ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.trigger[0].arn
}
