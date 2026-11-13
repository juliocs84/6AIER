output "vm_name" {
  description = "Nome da instância EC2"
  value       = var.vm_name
}

output "instance_id" {
  description = "ID da instância EC2"
  value       = aws_instance.vm.id
}

output "public_ip_address" {
  description = "IP público da instância"
  value       = aws_instance.vm.public_ip
}

output "ssh_command" {
  description = "Comando pronto para conectar na VM a partir do CloudShell"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.vm.public_ip}"
}

output "resource_group_name" {
  description = "Resource Group (consulta por tag) com os recursos desta stack"
  value       = aws_resourcegroups_group.lab.name
}

output "sg_web_id" {
  description = "Security group da VM (origem autorizada no sg-app)"
  value       = aws_security_group.web.id
}

output "sg_app_id" {
  description = "Security group da camada de aplicação (8080 só a partir do sg da VM)"
  value       = aws_security_group.app.id
}

output "ssh_liberado_para" {
  description = "CIDR liberado na porta 22"
  value       = "${var.meu_ip}/32"
}
