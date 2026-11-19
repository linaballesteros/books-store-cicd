locals {
  bootstrap_files = [
    "rds/bootstrap.sh",
    "rds/create_roles.sql",
    "rds/grants.sql",
    "rds/verify.sql",
    "schema.sql",
    "seed.sql",
  ]

  bootstrap_command = templatefile("${path.module}/bootstrap-command.tftpl", {
    files = { for name in local.bootstrap_files : name => file("${path.module}/../database/${name}") }
  })
}

resource "aws_ecs_task_definition" "bootstrap" {
  family                   = "${local.name_prefix}-db-bootstrap"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([{
    name       = "bootstrap"
    image      = "postgres:17-bookworm"
    essential  = true
    entryPoint = ["/bin/bash", "-ec"]
    command    = [local.bootstrap_command]
    environment = [for name, value in {
      DB_HOST       = aws_db_instance.database.address
      DB_PORT       = tostring(local.db_port)
      DB_NAME       = aws_db_instance.database.db_name
      DB_ADMIN_USER = aws_db_instance.database.username
      APP_DB_USER   = local.db_app_user
      PGSSLMODE     = "require"
    } : { name = name, value = value }]
    secrets = [for name, parameter in {
      DB_ADMIN_PASSWORD  = aws_ssm_parameter.db_admin_password.arn
      APP_DB_PASSWORD    = aws_ssm_parameter.db_app_password.arn
      INGEST_DB_PASSWORD = aws_ssm_parameter.db_ingest_password.arn
    } : { name = name, valueFrom = parameter }]
    logConfiguration = {
      logDriver = "awslogs"
      options   = merge(local.ecs_log_options, { awslogs-stream-prefix = "database" })
    }
  }])
}

output "bootstrap_task" {
  description = "ECS run-task input for the one-off database bootstrap."
  value = {
    cluster        = aws_ecs_cluster.app.name
    taskDefinition = aws_ecs_task_definition.bootstrap.arn
    launchType     = "FARGATE"
    networkConfiguration = {
      awsvpcConfiguration = {
        subnets        = data.aws_subnets.public.ids
        securityGroups = [aws_security_group.app.id]
        assignPublicIp = "ENABLED"
      }
    }
  }
}

output "aws_region" {
  description = "AWS region for commands that operate on the deployed resources."
  value       = var.aws_region
}
