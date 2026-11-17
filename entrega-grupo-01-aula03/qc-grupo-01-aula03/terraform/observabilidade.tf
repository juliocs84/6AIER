# Ex. 2.3c — Alarme sobre a métrica Errors de cada tool (>= 1 erro em 5 min).
# Errors conta exceções não tratadas e timeouts. Um 400/404 devolvido pelo código
# é resposta normal (não conta): por isso a tool valida a entrada e responde 400.

resource "aws_sns_topic" "alertas" {
  name = "${local.nome}-alertas"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alerta_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alertas.arn
  protocol  = "email"
  endpoint  = var.alerta_email # a AWS manda um e-mail de confirmação
}

locals {
  funcoes_monitoradas = {
    catalogo = aws_lambda_function.catalogo.function_name
    frete    = aws_lambda_function.frete.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "erros" {
  for_each = local.funcoes_monitoradas

  alarm_name          = "${each.value}-erros"
  alarm_description   = "Tool ${each.key} da QC com erro (exceção ou timeout) nos últimos 5 min"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching" # sem chamadas não é erro
  alarm_actions       = [aws_sns_topic.alertas.arn]
  ok_actions          = [aws_sns_topic.alertas.arn]
}
