#!/usr/bin/env bash
# Clean teardown of the AWS DevOps Agent EKS lab.
# Order matters: Kubernetes-created resources first, then Terraform, then leftovers.
set -euo pipefail
cd "$(dirname "$0")"

REGION="${REGION:-eu-central-1}"
CLUSTER="${CLUSTER:-devops-agent-lab-eks}"

echo "==> 1/4 Deleting the app (PVC → the MongoDB EBS volume is deleted by the CSI driver)"
if kubectl get ns pets >/dev/null 2>&1; then
  kubectl delete -f k8s/scenarios/ --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f k8s/base/application.yaml --ignore-not-found --wait=true
  echo "    waiting 30s for the EBS volume to be released..."
  sleep 30
fi

echo "==> 2/4 terraform destroy (EKS, node group, add-ons, alarms, SNS, VPC)"
terraform destroy ${AUTO_APPROVE:+-auto-approve}   # AUTO_APPROVE=1 in CI (approval happens in GitHub)

echo "==> 3/4 Deleting Container Insights log groups (created by the agent, not Terraform)"
for lg in $(aws logs describe-log-groups --region "$REGION" \
    --log-group-name-prefix "/aws/containerinsights/$CLUSTER" \
    --query 'logGroups[].logGroupName' --output text); do
  echo "    $lg"; aws logs delete-log-group --region "$REGION" --log-group-name "$lg"
done

echo "==> 4/4 Checking for orphaned EBS volumes from the cluster"
aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
  --query 'Volumes[].[VolumeId,Size,State]' --output table || true
echo "Done. Anything listed above is an orphan: aws ec2 delete-volume --volume-id <id> --region $REGION"
