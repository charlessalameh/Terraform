"""
SNS (CloudWatch alarm) -> AWS DevOps Agent webhook.

Adapted from aws-samples/sample-aws-genai-ops-demos (MIT-0),
observability/eks-investigation-devops-agent/cdk/lambda/devops-agent-trigger.

The payload deliberately does NOT tell the agent what is wrong: it forwards the alarm
and lets the agent find the root cause on its own (same as the Azure lab).
"""
import base64
import hashlib
import hmac
import json
import logging
import os
from datetime import datetime, timezone
from urllib import error, request

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_secret_cache = None


def get_secret(refresh: bool = False) -> str:
    global _secret_cache
    if _secret_cache is None or refresh:
        sm = boto3.client("secretsmanager")
        _secret_cache = sm.get_secret_value(SecretId=os.environ["SECRET_ARN"])["SecretString"].strip()
    return _secret_cache


def sign(secret: str, timestamp: str, body: str) -> str:
    """HMAC-SHA256 over '<timestamp>:<body>', base64 — the DevOps Agent webhook scheme."""
    digest = hmac.new(secret.encode(), f"{timestamp}:{body}".encode(), hashlib.sha256).digest()
    return base64.b64encode(digest).decode()


def _send(body: str, secret: str):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    req = request.Request(
        os.environ["WEBHOOK_URL"],
        data=body.encode(),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "x-amzn-event-timestamp": ts,
            "x-amzn-event-signature": sign(secret, ts, body),
        },
    )
    with request.urlopen(req, timeout=15) as resp:
        return resp.status, resp.read().decode()


def post_to_agent(payload: dict):
    body = json.dumps(payload)
    try:
        return _send(body, get_secret())
    except error.HTTPError as e:
        if e.code not in (401, 403):
            logger.error("Webhook HTTP %s: %s", e.code, e.read().decode())
            raise
        # Secret may have been rotated since this container cached it: re-read once and retry
        logger.warning("Webhook HTTP %s — re-reading secret and retrying once", e.code)
    try:
        return _send(body, get_secret(refresh=True))
    except error.HTTPError as e:
        logger.error("Webhook HTTP %s: %s (check the secret in Secrets Manager matches the webhook)", e.code, e.read().decode())
        raise


def priority(name: str, desc: str) -> str:
    text = f"{name} {desc}".lower()
    if any(w in text for w in ("oom", "crash", "database", "mongodb")):
        return "CRITICAL"
    if any(w in text for w in ("image", "pending", "error")):
        return "HIGH"
    return "MEDIUM"


def handler(event, context):
    cluster = os.environ["EKS_CLUSTER_NAME"]
    namespace = os.environ["APP_NAMESPACE"]
    region = os.environ["AWS_REGION"]
    sent = 0

    for record in event.get("Records", []):
        msg = record.get("Sns", {}).get("Message", "")
        try:
            alarm = json.loads(msg)
        except json.JSONDecodeError:
            alarm = {"AlarmName": "CloudWatch alarm", "AlarmDescription": msg, "NewStateValue": "ALARM", "NewStateReason": msg}

        if alarm.get("NewStateValue") != "ALARM":  # ignore OK / INSUFFICIENT_DATA notifications
            logger.info("Skipping state %s", alarm.get("NewStateValue"))
            continue

        name = alarm.get("AlarmName", "unknown")
        desc = alarm.get("AlarmDescription", "")
        payload = {
            "eventType": "incident",
            "incidentId": f"{name}-{context.aws_request_id}",
            "action": "created",
            "priority": priority(name, desc),
            "title": f"CloudWatch alarm: {name}",
            "description": (
                f"CloudWatch alarm '{name}' fired in {region}.\n"
                f"Description: {desc}\n"
                f"Reason: {alarm.get('NewStateReason', '')}\n\n"
                f"EKS cluster: {cluster}\nKubernetes namespace: {namespace}\nRegion: {region}"
            ),
            "timestamp": alarm.get("StateChangeTime", datetime.now(timezone.utc).isoformat()),
            "service": "cloudwatch",
            "data": {
                "alarmName": name,
                "alarmArn": alarm.get("AlarmArn", ""),
                "newStateReason": alarm.get("NewStateReason", ""),
                "clusterName": cluster,
                "namespace": namespace,
                "region": region,
            },
        }
        status, resp = post_to_agent(payload)
        logger.info("Sent %s to DevOps Agent: %s %s", payload["incidentId"], status, resp)
        sent += 1

    return {"statusCode": 200, "sent": sent}
