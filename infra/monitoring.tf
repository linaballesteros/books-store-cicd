variable "api_alarm_topic_arn" {
  description = "Optional existing SNS topic that receives API Gateway alarm notifications."
  type        = string
  default     = ""
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${local.name_prefix}-api-5xx"
  alarm_description   = "API Gateway returned at least one server error in two of the last three minutes."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.app.id
  }

  alarm_actions = trimspace(var.api_alarm_topic_arn) == "" ? [] : [var.api_alarm_topic_arn]
}
