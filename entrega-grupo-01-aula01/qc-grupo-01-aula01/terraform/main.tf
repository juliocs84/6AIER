terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# No AWS Academy Learner Lab as credenciais já vêm do CloudShell (LabRole).
# default_tags aplica as tags em TODOS os recursos — FinOps desde a Aula 1.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

locals {
  tags = {
    aula         = "1"
    disciplina   = "cloud-cognitive"
    projeto      = "quantum-commerce"
    provisionado = "terraform"
    stack        = var.stack_name
  }
}

# ---------------------------------------------------------------------------
# Rede — usamos a VPC padrão da conta (o Learner Lab já traz uma por região).
# Na Azure era preciso criar VNet + subnet; aqui ela já existe.
# ---------------------------------------------------------------------------
data "aws_vpc" "padrao" {
  default = true
}

# Imagem: Ubuntu Server 24.04 LTS (x86_64), publicada pela Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group com as 3 portas de entrada do lab via console (SSH, HTTP, HTTPS)
resource "aws_security_group" "web" {
  name        = "${var.vm_name}-sg" # a AWS proíbe nome começando com "sg-" (prefixo reservado aos IDs)
  description = "SSH, HTTP e HTTPS para a VM do lab da Aula 1"
  vpc_id      = data.aws_vpc.padrao.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # Ex. 3.1 — SSH só a partir do IP público de quem opera (CloudShell), nunca 0.0.0.0/0
    cidr_blocks = ["${var.meu_ip}/32"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Saida liberada"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Key pair a partir da chave pública do CloudShell (~/.ssh/id_rsa.pub)
resource "aws_key_pair" "lab" {
  key_name   = "key-${var.vm_name}"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# ---------------------------------------------------------------------------
# A máquina virtual — mesma configuração da Atividade 4 (console)
# ---------------------------------------------------------------------------
resource "aws_instance" "vm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.lab.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  # IMDSv2 obrigatório — boa prática de segurança
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = var.vm_name
  }
}

# ---------------------------------------------------------------------------
# "Resource Group" da AWS: não é uma pasta, é uma CONSULTA por tag.
# Apagar o grupo não apaga nada — quem apaga é o terraform destroy.
# ---------------------------------------------------------------------------
resource "aws_resourcegroups_group" "lab" {
  name        = "rg-iac-aula01"
  description = "Recursos da Aula 1 provisionados via Terraform - consulta por tag" # só letras, números, espaço, _ . -

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [{
        Key    = "stack"
        Values = [var.stack_name]
      }]
    })
  }
}

# ---------------------------------------------------------------------------
# Ex. 3.1 — sg-app: futura camada de aplicação da QC.
# Só aceita 8080 vindo do SECURITY GROUP da VM (referência entre SGs, não CIDR):
# se o IP da VM mudar, a regra continua valendo; nada de fora da VM alcança a app.
# Obs.: a AWS proíbe o NOME do SG começar com "sg-", então "sg-app" vai na tag Name.
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.vm_name}-app-sg"
  description = "Camada de aplicacao QC - 8080 somente a partir do SG da VM"
  vpc_id      = data.aws_vpc.padrao.id

  tags = {
    Name = "sg-app"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_8080_from_web" {
  security_group_id            = aws_security_group.app.id
  description                  = "8080 somente a partir do SG da VM"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.web.id
}

resource "aws_vpc_security_group_egress_rule" "app_all_out" {
  security_group_id = aws_security_group.app.id
  description       = "Saida liberada"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
