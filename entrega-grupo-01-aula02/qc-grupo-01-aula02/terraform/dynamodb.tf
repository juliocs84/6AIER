# DynamoDB — o NoSQL da QC. On-demand: paga por requisição, sem capacidade parada.
# Chave de partição produto_id: todas as reviews de um produto ficam na mesma "gaveta".
resource "aws_dynamodb_table" "reviews" {
  name         = "${local.nome}-reviews"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "produto_id"
  range_key    = "review_id"

  attribute {
    name = "produto_id"
    type = "N"
  }

  attribute {
    name = "review_id"
    type = "S"
  }

  # Ex. 2.3c — "todas as reviews de um cliente": sem este índice, só com Scan.
  # GSI = outra chave de partição sobre os MESMOS itens, mantida pelo DynamoDB
  # (consistência eventual). Os itens do lab já gravam o atributo "cliente".
  attribute {
    name = "cliente"
    type = "S"
  }

  global_secondary_index {
    name            = "por_cliente"
    hash_key        = "cliente"
    range_key       = "review_id"
    projection_type = "INCLUDE"
    # só o necessário para a tela "minhas reviews": evita duplicar o item inteiro
    non_key_attributes = ["produto_id", "score", "texto"]
  }
}
