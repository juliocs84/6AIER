# Bucket S3 — base de tudo da QC (equivale ao Storage Account + containers)
# Criado pela AWS CLI dentro do módulo: o SCP do Learner Lab nega
# s3:GetBucketObjectLockConfiguration, que o aws_s3_bucket lê a cada refresh.
# Detalhes em modulos/bucket-s3/main.tf (o destroy também esvazia o bucket).
module "bucket_qc" {
  source = "../../../../modulos/bucket-s3"
  nome   = local.nome
  regiao = var.region
}

# Nada público: bloqueia ACL e policy públicas
resource "aws_s3_bucket_public_access_block" "qc" {
  bucket                  = module.bucket_qc.nome
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Criptografia em repouso com chave gerenciada pelo S3
resource "aws_s3_bucket_server_side_encryption_configuration" "qc" {
  bucket = module.bucket_qc.nome
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Os "containers" viram prefixos. No S3 não existe pasta: o objeto vazio
# terminado em "/" só serve para o prefixo aparecer no console.
# raw/ e curated/ são as camadas do data lake do Lab 1B (fora do lifecycle de logs/).
resource "aws_s3_object" "prefixos" {
  for_each = toset(["catalogo/", "imagens/", "logs/", "logs-compras/", "raw/", "curated/"])
  bucket   = module.bucket_qc.nome
  key      = each.value
  content  = ""
}

# Lifecycle: logs migram para classes mais baratas e expiram em 1 ano
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = module.bucket_qc.nome

  rule {
    id     = "logs-lifecycle"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  # Ex. 1.2 — logs de compras: 30 dias em Standard (detecção de fraude) e depois
  # Deep Archive (compliance LGPD) até completar 5 anos.
  # Deep Archive exige 180 dias de permanência mínima e cobra por transição
  # (por objeto): agrupar os logs em arquivos grandes antes de arquivar.
  rule {
    id     = "logs-compras-deep-archive"
    status = "Enabled"

    filter {
      prefix = "logs-compras/"
    }

    transition {
      days          = 30
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 1826 # 5 anos (inclui 1 dia de ano bissexto)
    }
  }

  rule {
    id     = "abortar-multipart-incompleto"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
