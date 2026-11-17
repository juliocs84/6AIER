# Ex. 3.4 — Fargate em produção. Tudo atrás de var.producao_extras (default false),
# para o apply básico do lab continuar igual.
#   terraform apply -var="ecs_enabled=true" -var="producao_extras=true"

locals {
  extras      = var.producao_extras ? 1 : 0
  com_servico = var.producao_extras && var.ecs_enabled ? 1 : 0
}

# --- (c) Segredo injetado pelo ECS, nunca em "environment" -------------------
resource "random_password" "api_parceiro" {
  count   = local.extras
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "api_parceiro" {
  count                   = local.extras
  name                    = "${local.nome}/api-parceiro-frete"
  description             = "Chave fictícia da transportadora parceira (Ex. 3.4c)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "api_parceiro" {
  count         = local.extras
  secret_id     = aws_secretsmanager_secret.api_parceiro[0].id
  secret_string = random_password.api_parceiro[0].result
}

# --- (b) Right-sizing: variante 1 vCPU / 2 GB, já com o bloco "secrets" -------
resource "aws_ecs_task_definition" "produtos_api_1vcpu" {
  count                    = local.extras
  family                   = "${local.nome}-produtos-api-1vcpu"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"                    # 1 vCPU
  memory                   = "2048"                    # 2 GB
  execution_role_arn       = data.aws_iam_role.lab.arn # é ELA que lê o segredo na partida
  task_role_arn            = data.aws_iam_role.lab.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "produtos-api"
    image        = "${aws_ecr_repository.produtos_api.repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "BUCKET_NAME", value = module.bucket_catalogo.nome },
      { name = "CSV_KEY", value = aws_s3_object.produtos.key },
    ]
    # O valor NÃO fica na task definition: só o ARN. O agente do ECS busca o valor
    # no Secrets Manager ao iniciar a tarefa e entrega como variável de ambiente.
    secrets = [
      { name = "API_PARCEIRO_FRETE", valueFrom = aws_secretsmanager_secret.api_parceiro[0].arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "api-1vcpu"
      }
    }
  }])
}

# --- (a) Job batch: tarefa avulsa agendada (roda e termina) -------------------
resource "aws_ecs_task_definition" "recomendacoes_batch" {
  count                    = local.extras
  family                   = "${local.nome}-recomendacoes-batch"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.lab.arn
  task_role_arn            = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([{
    name      = "recomendacoes"
    image     = "${aws_ecr_repository.produtos_api.repository_url}:${var.image_tag}"
    essential = true
    # Reaproveita a imagem do lab só para demonstrar: em produção seria o job real
    command = ["python", "-c", "import time; print('Recalculando recomendações da QC...'); time.sleep(20); print('Concluído')"]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "batch"
      }
    }
  }])
}

resource "aws_scheduler_schedule" "recomendacoes_noturnas" {
  count       = local.extras
  name        = "${local.nome}-recomendacoes-noturnas"
  description = "RunTask diário às 3h (São Paulo): recalcula recomendações e termina"

  schedule_expression          = "cron(0 3 * * ? *)"
  schedule_expression_timezone = "America/Sao_Paulo"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_ecs_cluster.qc.arn
    role_arn = data.aws_iam_role.lab.arn # produção: role do Scheduler com ecs:RunTask + iam:PassRole

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.recomendacoes_batch[0].arn
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = data.aws_subnets.padrao.ids
        security_groups  = [aws_security_group.api.id]
        assign_public_ip = true # precisa puxar a imagem do ECR (sem NAT na VPC padrão)
      }
    }

    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}

# --- (d) Auto scaling do serviço: target tracking em CPU 60% -------------------
resource "aws_appautoscaling_target" "api" {
  count              = local.com_servico
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.qc.name}/${aws_ecs_service.produtos_api[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 10
}

resource "aws_appautoscaling_policy" "api_cpu" {
  count              = local.com_servico
  name               = "${local.nome}-cpu-60"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.api[0].service_namespace
  resource_id        = aws_appautoscaling_target.api[0].resource_id
  scalable_dimension = aws_appautoscaling_target.api[0].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_out_cooldown = 60  # sobe rápido no pico
    scale_in_cooldown  = 300 # desce devagar para não oscilar

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
