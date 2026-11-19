resource "aws_lb" "app" {
  name               = "${local.name_prefix}-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  depends_on = [
    aws_apigatewayv2_stage.app,
    aws_apigatewayv2_vpc_link.app,
    aws_s3_bucket_policy.alb_logs,
    aws_s3_bucket_server_side_encryption_configuration.alb_logs,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${local.name_prefix}-private-web"
  vpc_id               = data.aws_vpc.default.id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.frontend_port
  deregistration_delay = 30

  health_check {
    path = "/"
  }

  lifecycle {
    create_before_destroy = true
  }
}
