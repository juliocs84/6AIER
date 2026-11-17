variable "region" {
  description = "Região da AWS (o Learner Lab libera us-east-1 e us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "ecs_enabled" {
  description = "Quando true, cria o serviço ECS Fargate. Deixe false no primeiro apply: a imagem precisa estar no ECR antes"
  type        = bool
  default     = false
}

variable "image_tag" {
  description = "Tag da imagem no ECR usada pela tarefa Fargate"
  type        = string
  default     = "v1"
}

variable "producao_extras" {
  description = "Ex. 3.4: cria o segredo, a task definition 1 vCPU/2 GB com 'secrets', o job batch agendado e o auto scaling. Deixe false no lab básico"
  type        = bool
  default     = false
}

variable "alerta_email" {
  description = "Ex. 2.3: e-mail que recebe o alarme de erros (vazio = alarme sem notificação)"
  type        = string
  default     = ""
}
