############################################
# Phase 6 — Alarms (the AWS equivalent of the Azure lab's 1-minute log alerts)
#
# Source: Container Insights (enhanced observability) metrics from the
# amazon-cloudwatch-observability add-on, namespace "ContainerInsights".
# Each alarm uses a Metrics Insights SQL query so it sums over ALL pods in the
# app namespace — no need to know pod names in advance.
############################################
locals {
  app_namespace = "pets"

  # name => settings
  pod_alarms = {
    crashloop = {
      metric      = "pod_container_status_waiting_reason_crash_loop_back_off"
      description = "A container in ${local.app_namespace} is in CrashLoopBackOff"
      periods     = 1
    }
    oom-killed = {
      metric      = "pod_container_status_terminated_reason_oom_killed"
      description = "A container in ${local.app_namespace} was OOMKilled (memory limit hit)"
      periods     = 1
    }
    image-pull = {
      metric      = "pod_container_status_waiting_reason_image_pull_error"
      description = "A container in ${local.app_namespace} cannot pull its image"
      periods     = 1
    }
    pods-pending = {
      metric      = "pod_status_pending"
      description = "Pods in ${local.app_namespace} stuck Pending for 3 minutes (scheduling/capacity)"
      periods     = 3
    }
  }
}

# Where alarms go. Phase 7 adds the DevOps Agent webhook as a second target.
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # AWS sends a confirmation mail — click the link once
}

resource "aws_cloudwatch_metric_alarm" "pod" {
  for_each = local.pod_alarms

  alarm_name          = "${var.cluster_name}-${each.key}"
  alarm_description   = each.value.description
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = each.value.periods
  datapoints_to_alarm = each.value.periods
  treat_missing_data  = "notBreaching" # no data = healthy (metric only appears when something is wrong)

  metric_query {
    id          = "q1"
    return_data = true
    period      = 60
    expression  = "SELECT SUM(${each.value.metric}) FROM SCHEMA(ContainerInsights, ClusterName, Namespace, PodName) WHERE ClusterName = '${var.cluster_name}' AND Namespace = '${local.app_namespace}'"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "${var.cluster_name}-node-cpu-high"
  alarm_description   = "Average node CPU above 80% for 3 minutes"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "q1"
    return_data = true
    period      = 60
    expression  = "SELECT AVG(node_cpu_utilization) FROM SCHEMA(ContainerInsights, ClusterName, InstanceId, NodeName) WHERE ClusterName = '${var.cluster_name}'"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
