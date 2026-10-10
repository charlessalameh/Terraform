# Blind rerun — does the agent find the cause from evidence alone?

**Question (from a LinkedIn comment on Part 2):** in the first run the OOM manifest carried a `scenario: oom-killed`
label and the agent noticed it. How much of the answer came from evidence the agent gathered?

**Method:** rebuild the lab, run 3 incidents with **no hint labels**, and score each investigation on the evidence it
cites. Same app, same alarms, same agent configuration as run 1 (1 Oct 2026).

| # | Scenario | What breaks (ground truth) | How the agent is triggered | Why it's in the test |
|---|---|---|---|---|
| 1 | `oom-killed` | order-service memory limit 256Mi → 16Mi; OOMKilled exit 137 | `oom-killed` / `crashloop` alarm | Like-for-like rerun of run 1, without the label |
| 2 | `crash-loop` | product-service started with a command that prints "Starting with invalid config..." and exits 1 | `crashloop` alarm | A cause the agent has not seen; not a resource problem |
| 3 | `service-mismatch` | order-service **Service** selector matches no pods; pods stay healthy | **Symptom only**, sent by hand: "orders fail" | No alarm fires; hardest: needs endpoints, not pod status |

What the agent can still see, and that is fair: the alarm name and description describe the **symptom**
("a container was OOMKilled"), as a real alert would. The test is whether it finds the **cause** (which change, which
value, which revision) and proves it.

Time: ~3 h · Cost: ~$0.22/h infrastructure + ~$2–3 per investigation at list price (inside the free trial).

---

## A. Before you start (5 min, Mac)

```bash
cd ~/Projects/"AZ Practice"/Terraform
git checkout main && git pull
gh secret list -R charlessalameh/Terraform          # AWS_LAB_ROLE_ARN, LAB_ALERT_EMAIL (LAB_WEBHOOK_URL may be old: replaced in C)
```

Open a notes file for the scorecard (section H). Keep the GitHub Actions page and the AWS console (eu-central-1) open.

## B. Build the lab from the pipeline (~25 min)

1. GitHub → **Actions → AWS DevOps Agent lab → Run workflow** → `action = apply` → Run.
   > If `LAB_WEBHOOK_URL` still holds the old URL, delete it first (`gh secret delete LAB_WEBHOOK_URL -R charlessalameh/Terraform`):
   > the old webhook no longer exists and the first apply must create the Agent Space without the Lambda.
2. `plan` job → check the summary (≈ 73 to add, 0 destroy).
3. `apply` job → **Review deployments → aws-lab → Approve and deploy**.
4. Wait ~15–20 min. The run summary ends with nodes + pods. 📸 `B-apply-summary`
5. If a step fails on permissions, copy the error line and stop here (send it to me); fallback is a local `terraform apply`.

## C. Wire the agent (~20–60 min, mostly waiting)

1. Console → **AWS DevOps Agent** (eu-central-1) → Agent Spaces → `devops-agent-lab`. This is a **brand-new Agent
   Space**: no memory from run 1.
2. Wait until **"Learning your topology"** is finished (15–60 min). Don't break anything before. 📸 `C-topology`
3. Capabilities → Webhook → **Configure → Generate webhook → HMAC**. Copy the URL to a note.
4. Store the secret (Mac):
   ```bash
   export AWS_PROFILE=lab
   read -rs WEBHOOK_SECRET        # paste the secret, Enter
   aws secretsmanager put-secret-value --region eu-central-1 --secret-id devops-agent-lab/devops-agent-webhook --secret-string "$WEBHOOK_SECRET"; unset WEBHOOK_SECRET
   S=$(aws secretsmanager get-secret-value --region eu-central-1 --secret-id devops-agent-lab/devops-agent-webhook --query SecretString --output text); echo "length=${#S}"; unset S    # must be 44
   gh secret set LAB_WEBHOOK_URL -R charlessalameh/Terraform      # paste the new URL
   ```
5. **Run workflow → `apply`** again → approve → ~6 to add (trigger Lambda + SNS subscription).
6. Confirm the subscription email if AWS sends one.

## D. Baseline check (5 min)

```bash
aws eks update-kubeconfig --region eu-central-1 --name devops-agent-lab-eks
kubectl get pods -n pets                                      # all Running
aws cloudwatch describe-alarms --region eu-central-1 --alarm-name-prefix devops-agent-lab-eks --query 'MetricAlarms[].[AlarmName,StateValue]' --output table   # all OK
```

Wait until every alarm is **OK** (the store's start-up restarts can trip `crashloop` once). 📸 `D-baseline`

## E. Run 1 — OOM, blind (~25 min)

1. **Run workflow → `break` → scenario `oom-killed`** → approve. The run summary prints the break time = **T0**.
2. Prove it is blind:
   ```bash
   kubectl get deploy order-service -n pets --show-labels      # no scenario= / sre-demo= label
   kubectl get pods -n pets -w                                 # OOMKilled / CrashLoopBackOff (Ctrl+C)
   ```
   📸 `E1-no-labels`
3. Note **T1** alarm (CloudWatch → Alarms) and check the Lambda log line `Sent ... 200`.
4. DevOps Agent web app → Investigations → open the new one. Note **T2** investigation start and **T3** root cause.
   Let it finish. 📸 `E1-timeline`, `E1-root-cause`, `E1-mitigation`
5. Copy the investigation summary text into your notes (for the comparison).
6. **Run workflow → `restore`** → approve. Wait until both alarms are **OK** again (~5 min) before the next run.

## F. Run 2 — crash loop, blind (~25 min)

Same as E with **scenario `crash-loop`**. Blind check:
`kubectl get deploy product-service -n pets --show-labels`. Expected alarm: `crashloop`.
Ground truth the agent should reach: the new revision of product-service overrides the start command; the
container logs "Starting with invalid config..." and exits 1; fix = roll back. 📸 `F-…` as in E. Restore, wait for OK.

## G. Run 3 — silent failure, symptom only (~25 min)

1. **Run workflow → `break` → scenario `service-mismatch`** → approve (T0).
2. Show it is silent: `kubectl get pods -n pets` → all Running; alarms stay OK.
   `kubectl get endpoints order-service -n pets` → **no endpoints** (that's the truth the agent must find). 📸 `G-silent`
3. Report the symptom the way a user would — through the same Lambda, no hint of the cause:
   ```bash
   aws lambda invoke --region eu-central-1 --function-name devops-agent-lab-devops-agent-trigger --cli-binary-format raw-in-base64-out --payload '{"Records":[{"Sns":{"Message":"{\"AlarmName\":\"user-report-checkout-failing\",\"AlarmDescription\":\"Users report that placing an order in the store fails. The store page itself loads.\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"Reported by users\"}"}}]}' /tmp/out.json && cat /tmp/out.json
   ```
   Expect `{"statusCode": 200, "sent": 1}` (T1 = now).
4. Follow the investigation as in E (T2, T3, screenshots, copy the summary).
   Ground truth: Service `order-service` has no endpoints because its selector doesn't match the pod labels; pods are
   healthy; fix = restore the correct selector.
5. **`restore`** → approve → `kubectl get endpoints order-service -n pets` shows addresses again.

## H. Scorecard (fill in as you go)

| | Run 1 (1 Oct, label present) | Blind OOM | Blind crash loop | Blind service mismatch |
|---|---|---|---|---|
| T0 break | 10:01 | | | |
| T1 alarm / report | 10:04 (403 until 10:09) | | | |
| T2 investigation start | 10:10:37 | | | |
| T3 root cause (min after T2) | 2m10s | | | |
| Root cause correct? | Yes | | | |
| Evidence cited (events, exit code, limits, logs, rollout history, endpoints) | pod state, exit 137, limits 256Mi→16Mi, ReplicaSet revisions | | | |
| Mentioned any label/name as evidence? | Yes (noticed `scenario` label) | | | |
| Fix proposed and safe? | Yes, revision 3 | | | |
| Agent time / cost (Billing) | ~4–5 min | | | |

Verdict for the post: if the blind runs reach the same cause with the same kind of evidence, the label did not carry
the diagnosis. If they don't, that is the more interesting finding — report it as it is.

## I. Tear down (~20 min)

1. Console → Agent Space → Capabilities → **delete the webhook**.
2. **Run workflow → `destroy`**, confirm = `DESTROY-aws-lab` → approve.
3. Check: `aws eks list-clusters --region eu-central-1` → `[]`, and no `available` EBS volumes.
4. Next day: Billing → cost of the session (for the post).

## J. Close the loop

Reply to the comment with the scorecard (or a link to the post), and add the results to `docs/LAB-JOURNAL.md`.
