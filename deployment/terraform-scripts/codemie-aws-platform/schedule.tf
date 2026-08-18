resource "aws_autoscaling_schedule" "self-managed-stop" {
  for_each = var.workers_schedule_enabled ? module.eks.self_managed_node_groups : {}

  autoscaling_group_name = each.value.autoscaling_group_name
  scheduled_action_name  = "Stop"

  min_size         = 0
  max_size         = 0
  desired_capacity = 0

  time_zone  = var.workers_schedule_timezone
  recurrence = var.workers_schedule_stop_recurrence
}

resource "aws_autoscaling_schedule" "self-managed-start" {
  for_each = var.workers_schedule_enabled ? module.eks.self_managed_node_groups : {}

  autoscaling_group_name = each.value.autoscaling_group_name
  scheduled_action_name  = "Start"

  min_size         = each.value.autoscaling_group_min_size
  max_size         = each.value.autoscaling_group_max_size
  desired_capacity = each.value.autoscaling_group_desired_capacity

  time_zone  = var.workers_schedule_timezone
  recurrence = var.workers_schedule_start_recurrence
}

resource "aws_autoscaling_schedule" "eks-managed-stop" {
  for_each = var.workers_schedule_enabled ? module.eks.eks_managed_node_groups : {}

  autoscaling_group_name = each.value.autoscaling_group_name
  scheduled_action_name  = "Stop"

  min_size         = 0
  max_size         = 0
  desired_capacity = 0

  time_zone  = var.workers_schedule_timezone
  recurrence = var.workers_schedule_stop_recurrence
}

resource "aws_autoscaling_schedule" "eks-managed-start" {
  for_each = var.workers_schedule_enabled ? module.eks.eks_managed_node_groups : {}

  autoscaling_group_name = each.value.autoscaling_group_name
  scheduled_action_name  = "Start"

  min_size         = each.value.autoscaling_group_min_size
  max_size         = each.value.autoscaling_group_max_size
  desired_capacity = each.value.autoscaling_group_desired_capacity

  time_zone  = var.workers_schedule_timezone
  recurrence = var.workers_schedule_start_recurrence
}
