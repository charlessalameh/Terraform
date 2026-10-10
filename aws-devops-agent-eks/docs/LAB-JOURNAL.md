# Lab journal — AWS DevOps Agent on EKS

Running log of what I did, what broke and what I learned. Raw material for the write-up and LinkedIn post.

## Goal

Rebuild my Azure SRE Agent lab on AWS — **same app, same break scenarios, Terraform instead of Bicep** —
and compare how the **AWS DevOps Agent** investigates the same incidents as the **Azure SRE Agent**.

## Session 1 — 1 Oct 2026 · Phases 0–6

| Phase | Result |
|---|---|
| 0 | Lab added to my existing `Terraform` repo on branch `feature/aws-devops-agent-eks` |
| 2 | awscli 2.37, Terraform 1.16, kubectl, Helm 4 · IAM user `terraform-deployer`, profile `lab` · budget alert |
| 3 | VPC with 2 public subnets, IGW, no NAT — 7 resources, free |
| 4 | EKS 1.36, 2 × t4g.medium Graviton, 6 managed add-ons, Pod Identity for add-ons |
| 5 | Store app (12 pods) on arm64, MongoDB on an 8 GiB encrypted gp3 EBS volume |
| 6 | 5 CloudWatch alarms + SNS email; OOM test → alarm fired in ~3 min |

### What broke and how I fixed it

1. **PowerShell terminal** — `export` not recognised. VS Code had opened PowerShell; switched to zsh.
2. **Wrong AWS profile** — my keys were under profile `lab`, not `default`.
3. **`Invalid count argument` on plan** — with `kubernetes_version = null` the EKS module's node group
   can't know the version at plan time. Fix: pin it. `aws eks describe-cluster-versions --default-only` → **1.36**.
4. **EBS CSI add-on stuck in CREATING for 20 min, then timeout.** The node launch template enforces
   **IMDSv2 with hop limit 1** (good security default), so ordinary pods can't borrow the node's IAM role.
   I had put the EBS permissions on the node role, so the controller had no credentials.
   Fix: **one IAM role per add-on through EKS Pod Identity** (`addon-iam.tf`). Controller 6/6 Running within minutes.
   *Lesson: the "lab shortcut" was the bug; the best-practice design was also the working one.*
5. **Console: node group shows 0 nodes and "Unauthorized".** IAM and Kubernetes RBAC are separate layers in EKS.
   Only the Terraform identity had an access entry; my console identity didn't. Fix: `access_entries`.
   (Azure parallel: subscription Owner still needs an AKS RBAC role to see workloads.)
6. **Alarm stayed OK at first** — two reason-metrics (`oom_killed`, `image_pull_error`) don't exist until the
   event happens once, and alarms need 1–2 evaluation cycles. After the OOM test the metric appeared and the
   alarm went to ALARM.

### Azure → AWS translation table

| Azure lab | AWS lab |
|---|---|
| Bicep, subscription scope | Terraform, S3 remote state with native locking |
| AKS Free tier (control plane free) | EKS ($0.10/h control plane) |
| 1 system + 2 user D2s_v5 nodes | 2 × t4g.medium Graviton |
| Container Insights → Log Analytics | Container Insights (enhanced) → CloudWatch |
| 4 KQL log alerts, 1 min | 5 Metrics Insights SQL alarms, 1 min |
| Action group | SNS topic |
| `managed-csi` disk | gp3 EBS via EBS CSI + Pod Identity |
| Managed identity + RBAC | Pod Identity roles + EKS access entries |
| Azure SRE Agent (AAU billing, always-on fee) | AWS DevOps Agent (per-second investigation billing) |

### Timeline of the alarm test

| Event | Time |
|---|---|
| `kubectl apply -f k8s/scenarios/oom-killed.yaml` | t0 |
| First `OOMKilled` | t0 + 21 s |
| Metric `pod_container_status_terminated_reason_oom_killed` visible | ≈ t0 + 2 min |
| `devops-agent-lab-eks-oom-killed` → ALARM, email | ≈ t0 + 3 min |

## Session 1 (continued) — Phase 7–8 · DevOps Agent

### Phase 7 — wiring the agent
- 7a `terraform apply`: Agent Space, AgentSpaceRole (`AIDevOpsAgentAccessPolicy`), OperatorRole, AWS account
  association (monitor), EKS access entry with `AmazonAIOpsAssistantPolicy`, empty Secrets Manager secret — first try.
- 7b Console: Agent Space → Capabilities → Webhook → Generate (**HMAC**). URL + secret shown once.
- 7c `terraform apply`: trigger Lambda (arm64, Python) subscribed to the alarm SNS topic.
- "Learning your topology" took a while on first run (Resource Explorer setup) — not blocking.

**What broke:** the webhook answered `403 Invalid request`. The secret in Secrets Manager was 144 characters
starting with `aws ` — the clipboard still held the *command*, so `$(pbpaste)` stored the command as the secret.
Fix: `read -rs` prompt to paste the secret, verify length = 44. Lambda now re-reads the secret and retries once on 401/403.
SNS → Lambda retried each failed event twice (3 attempts per request ID), visible in the Lambda log.
*Lesson: always verify a stored secret by length/prefix — never by printing it.*

### Phase 8 — the OOM incident (fully automatic)

| Event | UTC |
|---|---|
| OOM scenario rolled out (order-service revision 4, limit 256Mi → 16Mi) | 10:01:25 |
| `…-oom-killed` alarm → first webhook call (403, wrong secret) | 10:04:01 |
| `…-crashloop` alarm (2 containers) | 10:07 |
| Secret fixed, event accepted by the webhook | 10:09:44 |
| **Investigation started** | **10:10:37** |
| Symptom identified (2 order-service pods, new ReplicaSet) | +1m23s |
| **Root cause found** (OOMKilled exit 137, 16Mi limit vs 64MB Node heap + OTel) | **+2m10s** |
| Rollout history table, rollback target = revision 3 | +2m23s |
| Mitigation plan delivered (kubectl patch to 256Mi/128Mi, pre/post checks, rollback step) | +3m57s |

**Agent's root cause (summary):** revision 4 of `order-service` cut the memory limit from 256Mi to 16Mi (request
8Mi). The Node.js process runs with `--max-old-space-size=64` plus four OpenTelemetry auto-instrumentation agents,
so every container is OOMKilled (exit 137) within ~1 s and loops in CrashLoopBackOff. Fix: roll back to revision 3
or patch limits to 256Mi/128Mi. Prevention: keep resources in version-controlled manifests, add a LimitRange /
admission policy. Gap it reported honestly: it could not identify *who* made the change (no CI/CD connected).

**How it investigated:** confirmed the alarm via AWS API → read its own memory of the agent space → `kubectl` pods
and events → spotted the 9-minute-old ReplicaSet among 90-minute-old pods → described the pods (OOMKilled, exit 137)
→ compared ReplicaSet revisions → handed off to a mitigation sub-agent.

**Fairness note:** the scenario manifest carries labels `scenario: oom-killed` and `sre-demo: breakable`, and the
agent noticed them. It still proved the mechanism from pod state, limits and rollout history — but for a blind test,
strip those labels (same applies to the Azure run, which used the same manifests).

### Azure SRE Agent vs AWS DevOps Agent — same OOM incident

| | Azure SRE Agent | AWS DevOps Agent |
|---|---|---|
| Trigger | Azure Monitor log alert → incident plan | CloudWatch alarm → SNS → Lambda → HMAC webhook |
| Alert → root cause | ~3 min (09:01 → 09:04) | ~2 min from investigation start (10:10:37 → 10:12:47) |
| Root cause | OOM after memory limit change, rollback | Same, plus the Node heap/OTel mechanism and a revision table |
| Fix | Proposed rollback, I approved, agent executed (Review mode) | Mitigation plan (kubectl patch) — I applied it |
| Kubernetes access | Managed identity + AKS RBAC | EKS access entry, `AmazonAIOpsAssistantPolicy` (read-only) |
| Billing | AAU: always-on fee (waived in eval) + active flow; Sev1 diagnosis 13 AAU | Per second of investigation, no idle fee |
| Setup effort | Portal onboarding, connectors, warm-up | Terraform (awscc) + one manual webhook step |
| Gotchas | Connectors failed until onboarding done; agent-created task cost 151 AAU | Webhook secret shown once; wrong secret = 403; topology learning delay |

## Next

- [ ] Restore app, confirm alarms return to OK
- [x] Actual cost: **about $2.50 for the whole session** (infrastructure + agent), covered by the AWS Free Tier
- [ ] Rebuild with screenshots (`_private/SCREENSHOT-RUNBOOK.md`), then `./destroy.sh`
- [ ] Optional blind test: remove scenario labels, try crash-loop / image-pull / pending
