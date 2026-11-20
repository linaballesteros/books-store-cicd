variable "release_images" {
  description = "Frontend and backend image references from the CI release manifest."
  type = object({
    frontend = string
    backend  = string
  })

  validation {
    condition = alltrue([
      for image in values(var.release_images) : can(regex("^[^@[:space:]]+@sha256:[0-9a-f]{64}$", image))
    ])
    error_message = "Both release images must be pinned to a SHA-256 digest."
  }
}

variable "auth_jwt_secret" {
  description = "Secret used by Express to sign JWTs for this environment."
  type        = string
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = length(trimspace(var.auth_jwt_secret)) >= 32
    error_message = "The JWT secret must contain at least 32 characters."
  }
}

variable "auth_jwt_secret_version" {
  description = "Increase this value when rotating the JWT signing secret."
  type        = number
  default     = 1
}

resource "aws_ssm_parameter" "auth_jwt_secret" {
  name             = "/bookstore/${local.environment}/auth/jwt-secret"
  type             = "SecureString"
  value_wo         = var.auth_jwt_secret
  value_wo_version = var.auth_jwt_secret_version
}

locals {
  backend_port = 5001
  api_prefix   = "/api"

  backend_env = {
    NODE_ENV                     = "production"
    SERVICE_NAME                 = "${local.name_prefix}-api"
    PORT                         = tostring(local.backend_port)
    API_BASE_PATH                = local.api_prefix
    CORS_ORIGINS                 = aws_apigatewayv2_api.app.api_endpoint
    BOOKS_DEFAULT_LIMIT          = "24"
    BOOKS_MAX_LIMIT              = "100"
    ORDERS_MAX_DISTINCT_ITEMS    = "100"
    ORDERS_MAX_QUANTITY_PER_ITEM = "1000"
    HTTP_TRUST_PROXY_HOPS        = "2"
    HTTP_JSON_BODY_LIMIT         = "32kb"
    ACCESS_LOG_ENABLED           = "true"
    ACCESS_LOG_EXCLUDE_PATHS     = "/health"
    ACCESS_LOG_MAX_FIELD_LENGTH  = "2048"
    ACCESS_LOG_REQUEST_ID_HEADER = "X-Request-Id"
    CLICKSTREAM_FILE_ENABLED     = "false"
    CLICKSTREAM_FILE_PATH        = "/usr/src/app/logs/clickstream.log"
    DB_HOST                      = aws_db_instance.database.address
    DB_PORT                      = tostring(local.db_port)
    DB_NAME                      = aws_db_instance.database.db_name
    DB_USER                      = local.db_app_user
    DB_SSL                       = "true"
    DB_SSL_REJECT_UNAUTHORIZED   = "false"
    DB_POOL_MAX                  = "10"
    DB_IDLE_TIMEOUT_MS           = "30000"
    DB_CONNECTION_TIMEOUT_MS     = "5000"
    AUTH_JWT_ALGORITHM           = "HS256"
    AUTH_JWT_ISSUER              = local.name_prefix
    AUTH_JWT_AUDIENCE            = "bookstore-web"
    AUTH_TOKEN_TTL_SECONDS       = "28800"
    AUTH_COOKIE_NAME             = "bookstore_session"
    AUTH_COOKIE_SECURE           = "true"
    AUTH_COOKIE_SAME_SITE        = "lax"
    AUTH_COOKIE_PATH             = local.api_prefix
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.lab.arn
  # Retain previous revisions so ECS can restore the previously deployed images.
  skip_destroy = true

  container_definitions = jsonencode([
    {
      name        = "backend"
      image       = var.release_images.backend
      essential   = true
      environment = [for name, value in local.backend_env : { name = name, value = value }]
      secrets = [
        { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_app_password.arn },
        { name = "AUTH_JWT_SECRET", valueFrom = aws_ssm_parameter.auth_jwt_secret.arn },
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:${local.backend_port}/health"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.ecs_log_options, { awslogs-stream-prefix = "app" })
      }
    },
    {
      name         = "frontend"
      image        = var.release_images.frontend
      essential    = true
      portMappings = [{ containerPort = local.frontend_port, protocol = "tcp" }]
      dependsOn    = [{ containerName = "backend", condition = "HEALTHY" }]
      environment = [
        { name = "NGINX_PORT", value = tostring(local.frontend_port) },
        { name = "API_PROXY_PREFIX", value = local.api_prefix },
        { name = "PROXY_PASS", value = "http://127.0.0.1:${local.backend_port}" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options   = merge(local.ecs_log_options, { awslogs-stream-prefix = "app" })
      }
    },
  ])
}

resource "aws_ecs_service" "app" {
  name                               = local.name_prefix
  cluster                            = aws_ecs_cluster.app.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = 0
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = local.frontend_port
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    # CD activates and restores revisions after database initialization.
    ignore_changes = [task_definition, desired_count]
  }
}

output "ecs_service_name" {
  description = "Service updated by the release and rollback steps."
  value       = aws_ecs_service.app.name
}

output "app_task_definition_arn" {
  description = "Candidate revision containing both images from the CI release."
  value       = aws_ecs_task_definition.app.arn
}
