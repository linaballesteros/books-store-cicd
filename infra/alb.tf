resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs, aws_s3_bucket_server_side_encryption_configuration.alb_logs]
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${local.name_prefix}-frontend"
  vpc_id               = data.aws_vpc.default.id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.frontend_port
  deregistration_delay = 30

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

output "alb_url" {
  description = "Base URL for the BookStore application and smoke tests."
  value       = "http://${aws_lb.app.dns_name}"
}
