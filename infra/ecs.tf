data "aws_iam_role" "lab" {
  name = "LabRole"
}

resource "aws_ecs_cluster" "app" {
  name = local.name_prefix
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 7
}

locals {
  ecs_log_options = {
    awslogs-group  = aws_cloudwatch_log_group.ecs.name
    awslogs-region = var.aws_region
  }
}

output "ecs_cluster_name" {
  description = "ECS cluster used by the bootstrap and application deployments."
  value       = aws_ecs_cluster.app.name
}
