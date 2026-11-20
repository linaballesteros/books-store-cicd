data "aws_vpc" "default" {
  default = true

  lifecycle {
    precondition {
      condition     = contains(["staging", "production"], local.environment)
      error_message = "Select the staging or production workspace before planning BookStore infrastructure."
    }
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }

  filter {
    name   = "availability-zone"
    values = ["${var.aws_region}a", "${var.aws_region}b"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) == 2
      error_message = "BookStore needs the default subnets in availability zones a and b for the ALB."
    }
  }
}

resource "aws_security_group" "alb" {
  name = "${local.name_prefix}-alb"
  # The existing group's description is immutable; its rules define access.
  description = "Public BookStore load balancer"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app"
  description = "BookStore Fargate application tasks"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.gateway_link.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80

  depends_on = [aws_apigatewayv2_vpc_link.app]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "gateway_link" {
  name        = "${local.name_prefix}-gateway-link"
  description = "API Gateway VPC Link to the private load balancer"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_egress_rule" "gateway_to_alb" {
  security_group_id            = aws_security_group.gateway_link.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.frontend_port
  to_port                      = local.frontend_port
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.frontend_port
  to_port                      = local.frontend_port
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  description       = "Docker Hub image pulls and CloudWatch Logs"
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
