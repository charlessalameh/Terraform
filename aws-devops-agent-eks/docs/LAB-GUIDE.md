# AWS DevOps Agent on EKS — step-by-step lab guide

Build a small but realistic EKS environment with Terraform, run a microservices app on it,
alert on failures with CloudWatch, and (Phase 7) let the **AWS DevOps Agent** investigate
incidents automatically. It is the AWS twin of my
[Azure SRE Agent lab](https://github.com/charlessalameh/Azure-sre-agent-sandbox): same app,
same break scenarios, so the two AI agents can be compared side by side.

![Architecture](diagrams/architecture.drawio.svg)

> The diagram is a `.drawio.svg`: it renders on GitHub and opens editable in
> [draw.io](https://app.diagrams.net) (File → Open → this file). `architecture.drawio` is the plain draw.io version.

| | |
|---|---|
| **Region** | eu-central-1 (Frankfurt) — one of the 6 AWS DevOps Agent regions |
| **IaC** | Terraform ≥ 1.10, AWS provider 6.x, `terraform-aws-modules/eks` v21 |
| **Cost** | ≈ $0.21–0.23/hour while running (see [Cost](#cost)) — destroy after every session |
| **Time** | ≈ 45 min for Phases 3–6 (EKS itself takes ~15 min) |

---

## Phase 0 — Repository layout

Everything lives in my existing Terraform repo, branch `feature/aws-devops-agent-eks`:

```
Terraform/
├── modules/networking/vpc-basic/   # reused VPC module (provider pin relaxed to >= 5.60, < 7.0)
└── aws-devops-agent-eks/
    ├── versions.tf  backend.tf  providers.tf  variables.tf  outputs.tf
    ├── network.tf        # Phase 3 — VPC
    ├── eks.tf            # Phase 4 — cluster, node group, add-ons, access entries
    ├── addon-iam.tf      # Phase 4 — Pod Identity roles for EBS CSI + CloudWatch
    ├── alarms.tf         # Phase 6 — CloudWatch alarms + SNS
    ├── k8s/base/         # Phase 5 — gp3 StorageClass + store app
    ├── k8s/scenarios/    # 10 break scenarios
    ├── destroy.sh        # clean teardown (incl. resources Kubernetes created)
    └── docs/             # this guide, journal, diagrams
```

Only `aws-devops-agent-eks/` is deployed. Do **not** run `bootstrap/` or `envs/test/` for this lab.

## Phase 2 — Prerequisites (Mac)

```bash
brew install awscli terraform kubectl helm
aws configure --profile lab        # IAM user with admin rights for the lab (never commit keys)
export AWS_PROFILE=lab             # add to ~/.zshrc to make it permanent
aws sts get-caller-identity        # must show your account
```

- Use **zsh/bash** in the VS Code terminal, not PowerShell (`export` does not exist there).
- Set a **budget alert** in Billing → Budgets before deploying anything.
- Terraform state bucket (S3, versioned, public access blocked) — create once if it does not exist:

```bash
aws s3api head-bucket --bucket tfstate-charles-demo --region us-east-1
# 404 → create it:
aws s3api create-bucket --bucket tfstate-charles-demo --region us-east-1
aws s3api put-bucket-versioning --bucket tfstate-charles-demo --versioning-configuration Status=Enabled
```

`backend.tf` uses `use_lockfile = true` (native S3 locking, Terraform ≥ 1.10 — no DynamoDB table needed).

## Phase 3 — Network (VPC)

`network.tf` calls the shared `vpc-basic` module: VPC `10.20.0.0/16`, two public `/20` subnets in
two AZs (EKS needs ≥ 2), internet gateway, route table. **No NAT gateway** — nodes get public IPs,
which saves ~$32/month in a lab. Subnets carry the tag `kubernetes.io/role/elb = 1`.

```bash
cd aws-devops-agent-eks
terraform init
terraform fmt && terraform validate
terraform plan        # Plan: 7 to add
terraform apply
terraform output      # vpc_id, public_subnet_ids
```

All 7 resources are free.

## Phase 4 — EKS cluster

`eks.tf` uses the community module `terraform-aws-modules/eks/aws` (~> 21.0):

| Part | Setting | Why |
|---|---|---|
| Control plane | Kubernetes **1.36**, public + private endpoint, secrets encrypted with a KMS key | Version pinned explicitly (see journal) |
| Access | `enable_cluster_creator_admin_permissions` + `access_entries` for the console user | IAM ≠ Kubernetes RBAC: both are needed |
| Node group | 2 × **t4g.medium** Graviton, AL2023 arm64, min 1 / max 3, IMDSv2 required, label `nodepool-type=user` | Cheapest sensible nodes; label matches the Azure manifests |
| Add-ons | `vpc-cni` (NetworkPolicy enabled), `eks-pod-identity-agent`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver`, `amazon-cloudwatch-observability` | Networking, storage for MongoDB, Container Insights |
| Add-on IAM | `addon-iam.tf`: one role per add-on via **EKS Pod Identity** | Pods cannot use the node role (IMDS hop limit 1) |

Check the current default EKS version first and set it in `variables.tf` (`kubernetes_version`):

```bash
aws eks describe-cluster-versions --region eu-central-1 --default-only --query 'clusterVersions[].clusterVersion' --output text
```

```bash
terraform init -upgrade      # downloads the EKS module
terraform plan               # ≈ 41 to add, VPC untouched
terraform apply              # 12–18 min (control plane ~10 min)

$(terraform output -raw kubeconfig_command)
kubectl get nodes -o wide    # 2 × Ready, arm64, v1.36
kubectl get pods -A          # all Running: aws-node, coredns, kube-proxy, ebs-csi-*, cloudwatch-agent, fluent-bit
```

## Phase 5 — Store app

The AKS Store Demo (MIT) ported to EKS — see the banner at the top of each manifest for the changes:
`managed-csi` → **gp3** StorageClass, `LoadBalancer` → **ClusterIP** (no cloud LB = no cost and a clean destroy),
MCR mirror images → **ECR Public**. All images are multi-arch, so they run on Graviton.

```bash
kubectl apply -f k8s/base/storageclass-gp3.yaml
kubectl apply -f k8s/base/application.yaml
kubectl get pods -n pets -w          # 12 pods Running after 2–3 min (1 order-service restart at start is normal)
kubectl get pvc -n pets              # mongodb-data-pvc Bound, 8Gi, gp3 → a real encrypted EBS volume

kubectl port-forward -n pets svc/store-front 8080:80     # http://localhost:8080
kubectl port-forward -n pets svc/store-admin 8081:80     # http://localhost:8081
```

`virtual-customer` places ~100 orders/hour, so CloudWatch sees real traffic.

## Phase 6 — Alarms

`alarms.tf` creates an SNS topic (+ optional email subscription) and five 1-minute alarms on
**Container Insights** metrics. Each alarm is a **Metrics Insights SQL** query that sums over every pod
in namespace `pets`:

| Alarm | Metric | Fires after | Scenario |
|---|---|---|---|
| `…-crashloop` | `pod_container_status_waiting_reason_crash_loop_back_off` | 1 min | crash-loop, missing-config |
| `…-oom-killed` | `pod_container_status_terminated_reason_oom_killed` | 1 min | oom-killed |
| `…-image-pull` | `pod_container_status_waiting_reason_image_pull_error` | 1 min | image-pull-backoff |
| `…-pods-pending` | `pod_status_pending` | 3 min | pending-pods |
| `…-node-cpu-high` | `node_cpu_utilization` (avg > 80 %) | 3 min | high-cpu |

```bash
export TF_VAR_alert_email="you@example.com"   # keeps the address out of git
terraform plan        # 7 to add
terraform apply       # then click "Confirm subscription" in the AWS email
```

**Test before adding the agent:**

```bash
kubectl apply -f k8s/scenarios/oom-killed.yaml
kubectl get pods -n pets -w                  # OOMKilled within ~20 s
aws cloudwatch describe-alarms --region eu-central-1 --alarm-name-prefix devops-agent-lab-eks --query 'MetricAlarms[].[AlarmName,StateValue]' --output table
# ~3 min later: devops-agent-lab-eks-oom-killed → ALARM, email arrives
kubectl apply -f k8s/base/application.yaml   # restore → alarm returns to OK
```

Some reason-metrics (`…_oom_killed`, `…_image_pull_error`) only appear in CloudWatch after the condition
has happened once — that is expected, the alarm treats missing data as healthy.

## Phase 7 — AWS DevOps Agent

`devops-agent.tf` (provider `awscc` ~> 1.104): Agent Space with operator web app, `AgentSpaceRole`
(`AIDevOpsAgentAccessPolicy`, trusts `aidevops.amazonaws.com` for this account only), `OperatorRole`, AWS account
association (monitor), EKS access entry with `AmazonAIOpsAssistantPolicy` (read-only), and a trigger Lambda
(SNS → HMAC-signed webhook). The webhook secret is shown once, so step 7b is manual and the secret never enters
Terraform state or git.

```bash
terraform init -upgrade && terraform apply                     # 7a: agent space, roles, association, access entry, empty secret
```

**7b — Console:** DevOps Agent (eu-central-1) → Agent Spaces → `devops-agent-lab` → Capabilities → Webhook →
Configure → Generate webhook → **HMAC**. Copy the URL; store the secret without echoing it:

```bash
read -rs WEBHOOK_SECRET          # paste the secret, Enter
aws secretsmanager put-secret-value --region eu-central-1 --secret-id "$(terraform output -raw webhook_secret_arn)" --secret-string "$WEBHOOK_SECRET"; unset WEBHOOK_SECRET
S=$(aws secretsmanager get-secret-value --region eu-central-1 --secret-id "$(terraform output -raw webhook_secret_arn)" --query SecretString --output text); echo "length=${#S}"; unset S   # must be 44
```

**7c — trigger Lambda:**

```bash
export TF_VAR_devops_agent_webhook_url="https://event-ai.eu-central-1.api.aws/webhook/generic/<id>"
terraform apply                                                  # ≈ 6 to add
```

First run: "Learning your topology" in the Agent Space can take 15–60 min (Resource Explorer setup).

## Phase 8 — Break it and watch the agent

```bash
kubectl apply -f k8s/scenarios/oom-killed.yaml
```

Alarm (~3 min) → SNS → Lambda (`Sent … 200` in its log) → investigation in the web app (Agent Space → Operator
access). In my run the agent stated the root cause **2 min 10 s** after the investigation started and delivered a
mitigation plan at ~4 min — see [LAB-JOURNAL.md](LAB-JOURNAL.md). Restore with `kubectl apply -f k8s/base/application.yaml`.

## Phase 9 — Teardown (≈ 20 min)

EKS has no "stop" — destroy after every session. The order matters, because some resources are created by
Kubernetes or by hand, not by Terraform.

**1. Commit first** (so nothing is lost if you rebuild later)

```bash
cd ~/Projects/"AZ Practice"/Terraform
git status                      # no .tfstate, .terraform/, .build/ or _private/ files must appear
git add -A aws-devops-agent-eks LICENSE .gitignore modules/networking/vpc-basic/versions.tf
git commit -m "AWS lab: phases 7-8 DevOps Agent, docs, license"
git push
```

**2. Restore the app** (no scenario left running → no new alarms → no new agent investigations)

```bash
cd aws-devops-agent-eks
kubectl apply -f k8s/base/application.yaml
kubectl get pods -n pets        # all Running
```

**3. Delete the webhook by hand** — DevOps Agent console → Agent Space `devops-agent-lab` → Capabilities →
Webhook → delete. Terraform did not create it, and it can block deleting the Agent Space.

**4. Run the teardown script**

```bash
export AWS_PROFILE=lab
./destroy.sh                    # type "yes" at the terraform destroy prompt
```

What it does:

| Step | Removes | Why not just `terraform destroy` |
|---|---|---|
| 1 | App + scenarios → PVC → the MongoDB EBS volume | The volume was created by the EBS CSI driver, not Terraform |
| 2 | `terraform destroy`: Lambda, webhook secret, Agent Space, IAM roles, alarms, SNS, EKS, add-ons, node group, KMS key (30-day pending deletion, free), VPC | — |
| 3 | `/aws/containerinsights/devops-agent-lab-eks/*` log groups | Created by the CloudWatch agent, kept forever otherwise |
| 4 | Lists any orphaned EBS volume of the cluster | Safety check |

**5. Verify nothing billable is left**

```bash
aws eks list-clusters --region eu-central-1                                                    # []
aws ec2 describe-instances --region eu-central-1 --filters Name=tag:Project,Values=devops-agent-lab Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text   # empty
aws ec2 describe-volumes --region eu-central-1 --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size]' --output text       # empty
aws ec2 describe-addresses --region eu-central-1 --query 'Addresses[].PublicIp' --output text   # empty
aws logs describe-log-groups --region eu-central-1 --log-group-name-prefix /aws/containerinsights --query 'logGroups[].logGroupName' --output text   # empty
aws cloudwatch describe-alarms --region eu-central-1 --alarm-name-prefix devops-agent-lab --query 'MetricAlarms[].AlarmName' --output text           # empty
terraform state list            # empty
```

**Intentionally kept** (free or cents): the S3 state bucket `tfstate-charles-demo`, the KMS key in pending deletion
(no charge), the Resource Explorer index and service-linked role the agent created (free), your budget alert.

**If `terraform destroy` fails**
- *Agent Space / association* error → the webhook still exists: delete it in the console, run `terraform destroy` again.
- *VPC / subnet DependencyViolation* → something Kubernetes created still holds a network interface (e.g. a
  LoadBalancer service): `aws ec2 describe-network-interfaces --region eu-central-1 --filters Name=vpc-id,Values=<vpc-id>`,
  delete the leftover, re-run.
- *Secret already scheduled for deletion* on the next rebuild → not expected (`recovery_window_in_days = 0`); if it
  happens: `aws secretsmanager delete-secret --secret-id devops-agent-lab/devops-agent-webhook --force-delete-without-recovery --region eu-central-1`.

## Cost

| Item | ≈ per hour (Frankfurt) |
|---|---|
| EKS control plane (standard support) | $0.100 |
| 2 × t4g.medium | $0.077 |
| 2 public IPv4 addresses | $0.010 |
| EBS gp3 (2 × 20 GiB nodes + 8 GiB MongoDB) | $0.006 |
| Container Insights + logs, control-plane logs | ~$0.02–0.04 |
| **Total** | **≈ $0.21–0.23/h (~$5/day)** |

Monthly, pro-rated: KMS key $1, five alarms ~$0.50–1.50, SNS email free, VPC free.
DevOps Agent (Phase 7): billed per second of investigation (~$30 per agent-hour), no idle fee.
Track the real spend: Billing → Cost allocation tags → activate `Lab` and `Project`, then filter Cost Explorer.

## Troubleshooting (things that actually happened)

See [LAB-JOURNAL.md](LAB-JOURNAL.md) for the full story. Short version:

| Symptom | Cause | Fix |
|---|---|---|
| `export: not recognized` | VS Code terminal was PowerShell | Switch the terminal to zsh |
| `config profile (default) could not be found` | Credentials saved under profile `lab` | `export AWS_PROFILE=lab` |
| `Invalid count argument` in the node-group module | `kubernetes_version = null` can't be planned | Pin the version (1.36) |
| `aws-ebs-csi-driver` stuck CREATING → 20 min timeout | IMDSv2 hop limit 1 blocks pods from the node role, so the controller had no credentials | Pod Identity role per add-on (`addon-iam.tf`) |
| Console shows 0 nodes / *Unauthorized* | Console user (root) had IAM rights but no EKS access entry | `access_entries` in `eks.tf` |
| `aws: Unknown options` | Multi-line command pasted with `\ ` mid-line | Paste as one line |
| Webhook `403 Invalid request` in the trigger Lambda log | Secret in Secrets Manager was the *command* (144 chars), not the secret | Store it with `read -rs`, check length = 44 |
