resource "aws_apigatewayv2_api" "app" {
  name          = local.name_prefix
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_vpc_link" "app" {
  name               = local.name_prefix
  security_group_ids = [aws_security_group.gateway_link.id]
  subnet_ids         = data.aws_subnets.public.ids
}

resource "aws_apigatewayv2_integration" "app" {
  api_id                 = aws_apigatewayv2_api.app.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = aws_lb_listener.http.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.app.id
  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

resource "aws_apigatewayv2_route" "app" {
  api_id    = aws_apigatewayv2_api.app.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_apigatewayv2_stage" "app" {
  api_id      = aws_apigatewayv2_api.app.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.ecs.arn
    format = jsonencode({
      requestId   = "$context.requestId"
      method      = "$context.httpMethod"
      status      = "$context.status"
      responseLen = "$context.responseLength"
    })
  }
}

output "application_url" {
  description = "Public HTTPS URL for BookStore and its smoke tests."
  value       = aws_apigatewayv2_api.app.api_endpoint
}
