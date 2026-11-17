output "bucket_name" {
  description = "Bucket do catálogo (já com catalogo/produtos.csv)"
  value       = module.bucket_catalogo.nome
}

output "lambda_name" {
  description = "Nome da função Lambda (usar no aws lambda update-function-code)"
  value       = aws_lambda_function.catalogo.function_name
}

output "function_url" {
  description = "URL HTTPS da função (termina com /)"
  value       = aws_lambda_function_url.catalogo.function_url
}

output "ecr_repository_url" {
  description = "Repositório ECR (destino do docker push)"
  value       = aws_ecr_repository.produtos_api.repository_url
}

output "ecs_cluster_name" {
  description = "Cluster ECS"
  value       = aws_ecs_cluster.qc.name
}

output "ecs_service_name" {
  description = "Serviço ECS quando habilitado"
  value       = var.ecs_enabled ? aws_ecs_service.produtos_api[0].name : "ECS desabilitado — depois do docker push, rode: terraform apply -var=\"ecs_enabled=true\""
}

output "frete_url" {
  description = "URL HTTPS da tool de frete (Ex. 2.2)"
  value       = aws_lambda_function_url.frete.function_url
}

output "frete_lambda_name" {
  description = "Nome da função de frete"
  value       = aws_lambda_function.frete.function_name
}

output "alarmes" {
  description = "Alarmes de Errors (Ex. 2.3c)"
  value       = [for a in aws_cloudwatch_metric_alarm.erros : a.alarm_name]
}

output "task_definition_1vcpu" {
  description = "Task definition 1 vCPU/2 GB com secrets (Ex. 3.4), quando producao_extras = true"
  value       = var.producao_extras ? aws_ecs_task_definition.produtos_api_1vcpu[0].arn : "producao_extras = false"
}
