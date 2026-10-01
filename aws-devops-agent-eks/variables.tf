############################################
# Inputs (defaults are the lab values; override with -var or a local *.tfvars)
############################################
variable "region" {
  description = "Lab region. Must be one of the AWS DevOps Agent regions."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Name prefix for resources."
  type        = string
  default     = "devops-agent-lab"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "charlie"
}

variable "vpc_cidr" {
  description = "VPC address space. EKS pods get IPs from these subnets (VPC CNI)."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "One public subnet per AZ (2 AZs). /20 = 4,091 usable IPs each."
  type        = list(string)
  default     = ["10.20.0.0/20", "10.20.16.0/20"]
}

# ---------- Phase 4: EKS ----------
variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "devops-agent-lab-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version. Must be set explicitly (the EKS module can't plan with null). Check: aws eks describe-cluster-versions --default-only"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "Worker node size. t4g.medium = 2 vCPU / 4 GiB Graviton."
  type        = string
  default     = "t4g.medium"
}

variable "node_count" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the EKS API. Set to [\"<your-public-ip>/32\"] to lock it down."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "console_admin_arns" {
  description = "IAM principal ARNs that get cluster-admin in EKS (console/kubectl). Empty = account root user."
  type        = list(string)
  default     = []
}

# ---------- Phase 6: alarms ----------
variable "alert_email" {
  description = "Email for alarm notifications. Keep it out of git: export TF_VAR_alert_email=you@example.com"
  type        = string
  default     = null
}

# ---------- Phase 7: DevOps Agent ----------
variable "devops_agent_webhook_url" {
  description = "Webhook URL generated in the DevOps Agent console (step 7b). null = trigger Lambda not created yet. Pass via TF_VAR_devops_agent_webhook_url."
  type        = string
  default     = null
}
