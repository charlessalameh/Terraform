output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

# ---------- Phase 4: EKS ----------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# ---------- Phase 6: alarms ----------
output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

# ---------- Phase 7: DevOps Agent ----------
output "agent_space_id" {
  value = awscc_devopsagent_agent_space.this.agent_space_id
}

output "agent_space_role_arn" {
  value = aws_iam_role.agent_space.arn
}

output "webhook_secret_arn" {
  description = "Put the webhook HMAC secret here in step 7b"
  value       = aws_secretsmanager_secret.webhook.arn
}

output "trigger_lambda" {
  value = local.trigger_enabled ? aws_lambda_function.trigger[0].function_name : "not created yet — set TF_VAR_devops_agent_webhook_url (step 7c)"
}
