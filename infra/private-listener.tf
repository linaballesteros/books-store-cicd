# API Gateway terminates public TLS. The ALB admits this HTTP traffic only
# from the security group attached to the VPC Link.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  lifecycle {
    create_before_destroy = true
  }
}
