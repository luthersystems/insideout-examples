terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}


locals {
  alarm_name_prefix = "${var.project}-monitoring"
}

# -----------------------------------------------------------------------------
# Alarm notifications
# -----------------------------------------------------------------------------
# A customer managed key encrypts the alarm topic (Trivy AWS-0095): alarm
# messages name the stack's instances, databases and queues. The AWS managed
# key aws/sns cannot be used here, because its key policy does not let
# CloudWatch publish to the topic; this key's policy does.
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "alarms_key" {
  # The account administers the key through IAM, as with any default key
  # policy, so the key can never become unmanageable.
  statement {
    sid       = "AccountAdministersKey"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch alarms in this account publish to the encrypted topic, which
  # needs a data key from this key.
  statement {
    sid       = "CloudWatchPublishesAlarms"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "alarms" {
  description             = "Encrypts the ${var.project} CloudWatch alarm topic"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.alarms_key.json
  tags                    = var.tags
}

resource "aws_sns_topic" "alarms" {
  name              = "${var.project}-cw-alarms"
  kms_master_key_id = aws_kms_key.alarms.arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "emails" {
  for_each  = toset(var.alarm_emails)
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# -----------------------------------------------------------------------------
# EC2 CPU alarms (bastion/VMs)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  # Use stable keys (indices) so the set of instances is known at plan time
  for_each = { for i in tolist(range(length(var.instance_ids))) : i => true }

  alarm_name                = "${local.alarm_name_prefix}-ec2-cpu-${replace(var.instance_ids[tonumber(each.key)], "/[^a-zA-Z0-9._-]/", "-")}"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = var.eval_periods
  threshold                 = var.cpu_high_threshold
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = var.period
  statistic                 = "Average"
  treat_missing_data        = "notBreaching"
  alarm_description         = "High CPU on EC2 instance ${var.instance_ids[tonumber(each.key)]}"
  dimensions                = { InstanceId = var.instance_ids[tonumber(each.key)] }
  alarm_actions             = [aws_sns_topic.alarms.arn]
  ok_actions                = [aws_sns_topic.alarms.arn]
  insufficient_data_actions = []
  tags                      = var.tags
}

# -----------------------------------------------------------------------------
# RDS alarms (CPU and FreeStorageSpace)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  # Same index-key trick to avoid unknown keys at plan time
  for_each = { for i in tolist(range(length(var.rds_instance_ids))) : i => true }

  alarm_name                = "${local.alarm_name_prefix}-rds-cpu-${var.rds_instance_ids[tonumber(each.key)]}"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = var.eval_periods
  threshold                 = var.cpu_high_threshold
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/RDS"
  period                    = var.period
  statistic                 = "Average"
  treat_missing_data        = "notBreaching"
  alarm_description         = "High CPU on RDS instance ${var.rds_instance_ids[tonumber(each.key)]}"
  dimensions                = { DBInstanceIdentifier = var.rds_instance_ids[tonumber(each.key)] }
  alarm_actions             = [aws_sns_topic.alarms.arn]
  ok_actions                = [aws_sns_topic.alarms.arn]
  insufficient_data_actions = []
  tags                      = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  for_each = { for i in tolist(range(length(var.rds_instance_ids))) : i => true }

  alarm_name                = "${local.alarm_name_prefix}-rds-freestorage-${var.rds_instance_ids[tonumber(each.key)]}"
  comparison_operator       = "LessThanThreshold"
  evaluation_periods        = var.eval_periods
  threshold                 = var.rds_free_storage_gb_threshold * 1024 * 1024 * 1024
  metric_name               = "FreeStorageSpace"
  namespace                 = "AWS/RDS"
  period                    = var.period
  statistic                 = "Average"
  treat_missing_data        = "notBreaching"
  alarm_description         = "Low free storage on RDS instance ${var.rds_instance_ids[tonumber(each.key)]}"
  dimensions                = { DBInstanceIdentifier = var.rds_instance_ids[tonumber(each.key)] }
  alarm_actions             = [aws_sns_topic.alarms.arn]
  ok_actions                = [aws_sns_topic.alarms.arn]
  insufficient_data_actions = []
  tags                      = var.tags
}

# -----------------------------------------------------------------------------
# ElastiCache / Redis CPU alarm
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  for_each = { for i in tolist(range(length(var.elasticache_replication_group_ids))) : i => true }

  alarm_name                = "${local.alarm_name_prefix}-redis-cpu-${var.elasticache_replication_group_ids[tonumber(each.key)]}"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = var.eval_periods
  threshold                 = var.cpu_high_threshold
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/ElastiCache"
  period                    = var.period
  statistic                 = "Average"
  treat_missing_data        = "notBreaching"
  alarm_description         = "High CPU on Redis RG ${var.elasticache_replication_group_ids[tonumber(each.key)]}"
  dimensions                = { CacheClusterId = var.elasticache_replication_group_ids[tonumber(each.key)] } # works per-node
  alarm_actions             = [aws_sns_topic.alarms.arn]
  ok_actions                = [aws_sns_topic.alarms.arn]
  insufficient_data_actions = []
  tags                      = var.tags
}

# -----------------------------------------------------------------------------
# SQS backlog alarm (visible messages)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "sqs_backlog" {
  # Use stable keys (indices) to avoid unknown set keys
  for_each = { for i in tolist(range(length(var.sqs_queue_arns))) : i => true }

  alarm_name          = "${local.alarm_name_prefix}-sqs-backlog-${replace(var.sqs_queue_arns[tonumber(each.key)], "/[:]/", "-")}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.eval_periods
  threshold           = var.sqs_backlog_threshold
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.period
  statistic           = "Average"
  treat_missing_data  = "notBreaching"
  alarm_description   = "SQS backlog high"
  dimensions = {
    QueueName = split(":", var.sqs_queue_arns[tonumber(each.key)])[length(split(":", var.sqs_queue_arns[tonumber(each.key)])) - 1]
  }
  alarm_actions             = [aws_sns_topic.alarms.arn]
  ok_actions                = [aws_sns_topic.alarms.arn]
  insufficient_data_actions = []
  tags                      = var.tags
}

# -----------------------------------------------------------------------------
# Dashboard (EC2, RDS, Redis, ALB, MSK)
# -----------------------------------------------------------------------------
locals {
  dash_metrics = concat(
    length(var.instance_ids) > 0 ? [
      {
        "type" : "metric", "x" : 0, "y" : 0, "w" : 24, "h" : 6,
        "properties" : {
          "title" : "EC2 CPU", "region" : var.region, "period" : var.period, "stat" : "Average",
          "metrics" : concat([["AWS/EC2", "CPUUtilization", { "stat" : "Average" }]],
            [for id in var.instance_ids : ["AWS/EC2", "CPUUtilization", "InstanceId", id, { "stat" : "Average" }]]
          )
        }
      }
    ] : [],
    length(var.rds_instance_ids) > 0 ? [
      {
        "type" : "metric", "x" : 0, "y" : 6, "w" : 24, "h" : 6,
        "properties" : {
          "title" : "RDS CPU", "region" : var.region, "period" : var.period, "stat" : "Average",
          "metrics" : concat([["AWS/RDS", "CPUUtilization", { "stat" : "Average" }]],
            [for id in var.rds_instance_ids : ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", id, { "stat" : "Average" }]]
          )
        }
      },
      {
        "type" : "metric", "x" : 0, "y" : 12, "w" : 24, "h" : 6,
        "properties" : {
          "title" : "RDS FreeStorage", "region" : var.region, "period" : var.period, "stat" : "Average",
          "metrics" : concat([["AWS/RDS", "FreeStorageSpace", { "stat" : "Average" }]],
            [for id in var.rds_instance_ids : ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", id, { "stat" : "Average" }]]
          )
        }
      }
    ] : [],
    length(var.elasticache_replication_group_ids) > 0 ? [
      {
        "type" : "metric", "x" : 0, "y" : 18, "w" : 24, "h" : 6,
        "properties" : {
          "title" : "Redis CPU", "region" : var.region, "period" : var.period, "stat" : "Average",
          "metrics" : concat([["AWS/ElastiCache", "CPUUtilization", { "stat" : "Average" }]],
            [for rg in var.elasticache_replication_group_ids : ["AWS/ElastiCache", "CPUUtilization", "ReplicationGroupId", rg, { "stat" : "Average" }]]
          )
        }
      }
    ] : [],
    length(var.alb_arn_suffixes) > 0 ? [
      {
        "type" : "metric", "x" : 0, "y" : 24, "w" : 24, "h" : 6,
        "properties" : {
          "title" : "ALB 5XX & Latency", "region" : var.region, "period" : var.period, "stat" : "Sum",
          "metrics" : concat(
            [["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", { "stat" : "Sum" }]],
            [for s in var.alb_arn_suffixes : ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", s, { "stat" : "Sum" }]],
            [[".", "TargetResponseTime", { "stat" : "Average" }]],
            [for s in var.alb_arn_suffixes : ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", s, { "stat" : "Average" }]]
          )
        }
      }
    ] : [],
    length(var.msk_cluster_arns) > 0 ? [
      {
        "type" : "metric", "x" : 0, "y" : 30, "w" : 24, "h" : 6,
        "properties" : {
          "title" : "MSK Bytes In/Out (per broker)", "region" : var.region, "period" : var.period, "stat" : "Average",
          "metrics" : concat(
            [["AWS/Kafka", "BytesInPerSec", { "stat" : "Average" }]],
            [for a in var.msk_cluster_arns : ["AWS/Kafka", "BytesInPerSec", "Cluster Name", a, { "stat" : "Average" }]],
            [[".", "BytesOutPerSec", { "stat" : "Average" }]],
            [for a in var.msk_cluster_arns : ["AWS/Kafka", "BytesOutPerSec", "Cluster Name", a, { "stat" : "Average" }]]
          )
        }
      }
    ] : []
  )
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-monitoring"
  dashboard_body = jsonencode({ widgets = local.dash_metrics })
}
