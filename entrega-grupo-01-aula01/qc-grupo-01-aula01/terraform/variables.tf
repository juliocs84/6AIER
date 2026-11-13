variable "region" {
  description = "Região da AWS (o Learner Lab libera us-east-1 e us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Valor da tag 'stack', usada pelo Resource Group para achar os recursos"
  type        = string
  default     = "iac-aula01"
}

variable "vm_name" {
  description = "Nome da instância EC2 (tag Name)"
  type        = string
  default     = "vm-lab-aula01"
}

variable "instance_type" {
  description = "Tipo da instância (o Learner Lab aceita de nano a large)"
  type        = string
  default     = "t3.micro"
}

variable "meu_ip" {
  description = "IP público de saída de quem opera (sem /32). No CloudShell: curl -s https://checkip.amazonaws.com"
  type        = string
  # sem default de propósito: o plan falha se ninguém informar o IP (fail-closed)

  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.meu_ip))
    error_message = "Informe apenas o IPv4 (ex.: 54.12.34.56), sem /32 e nunca 0.0.0.0."
  }

  validation {
    condition     = var.meu_ip != "0.0.0.0"
    error_message = "0.0.0.0 reabre o SSH para a internet inteira."
  }
}

variable "ssh_public_key_path" {
  description = "Chave pública SSH usada no key pair (no CloudShell: ~/.ssh/id_rsa.pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
