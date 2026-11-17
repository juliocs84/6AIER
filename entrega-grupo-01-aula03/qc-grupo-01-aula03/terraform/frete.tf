# Ex. 2.2 — Segunda tool dos agentes: calcular_frete, numa função SEPARADA.
# Por que separada: é pura (não lê S3, banco nem segredo), então em produção a role
# dela teria permissão de dados ZERO; deploy, escala e alarme ficam independentes da busca.

data "archive_file" "v3_frete" {
  type        = "zip"
  source_dir  = "${path.module}/../function/v3-frete"
  output_path = "${path.module}/.build/v3-frete.zip"
  excludes    = ["test_frete.py", "__pycache__"]
}

resource "aws_cloudwatch_log_group" "frete" {
  name              = "/aws/lambda/${local.nome}-frete"
  retention_in_days = 7
}

resource "aws_lambda_function" "frete" {
  function_name    = "${local.nome}-frete"
  role             = data.aws_iam_role.lab.arn # produção: role só com logs (ver iam/)
  runtime          = "python3.12"
  handler          = "lambda_function.lambda_handler"
  filename         = data.archive_file.v3_frete.output_path
  source_code_hash = data.archive_file.v3_frete.output_base64sha256
  timeout          = 5   # cálculo em memória: se passar de 5 s, algo está errado
  memory_size      = 128 # sem I/O: 128 MB bastam (ver Ex. 2.3d)

  depends_on = [aws_cloudwatch_log_group.frete]
}

resource "aws_lambda_function_url" "frete" {
  function_name      = aws_lambda_function.frete.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

resource "aws_lambda_permission" "frete_url_publica" {
  statement_id           = "FunctionUrlPublica"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.frete.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# Mesma segunda permissão do lab (InvokeFunction só via Function URL), pelo CLI
resource "terraform_data" "frete_url_invoke" {
  triggers_replace = [aws_lambda_function.frete.arn]

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda add-permission --region ${var.region} \
        --function-name ${aws_lambda_function.frete.function_name} \
        --statement-id FunctionUrlInvoke \
        --action lambda:InvokeFunction --principal '*' \
        --invoked-via-function-url >/dev/null 2>&1 \
      || echo "Permissão FunctionUrlInvoke já existe (ou CLI antigo) — seguindo."
    EOT
  }
}
