# Grupo 01 — Aula 02 · Como rodar o que foi entregue

Tudo no **AWS CloudShell**, com o Learner Lab iniciado e o lab da Aula 2 clonado em `~/aie-cloud`.

```bash
export AWS_PAGER=""                 # a AWS CLI não abre o "less"
cd ~ && unzip -o entrega-grupo-01-aula02.zip     # depois de Actions → Upload file
E=~/qc-grupo-01-aula02
LAB=~/aie-cloud/aulas/02-storage-bancos/lab
```

## Terraform evoluído (Ex. 1.2 e 2.3c)

Os dois arquivos substituem os do lab. O módulo do bucket usa caminho relativo ao repositório, então rode **dentro da pasta do lab**.

```bash
cp "$E/terraform/dynamodb.tf" "$E/terraform/storage.tf" "$LAB/terraform/"
cd "$LAB/terraform"
source ../qc.sh                      # recupera DB_PASSWORD, outputs e o venv
terraform plan -var="db_password=$DB_PASSWORD" | tee ~/plan-aula02.txt
#   esperado: ~ aws_dynamodb_table.reviews (update in-place: + GSI por_cliente)
#             ~ aws_s3_bucket_lifecycle_configuration.logs (+ 2 regras)
#             + aws_s3_object.prefixos["logs-compras/"]
terraform apply -var="db_password=$DB_PASSWORD" -auto-approve

# testar o GSI (Ex. 2.3c) — reviews de um cliente sem Scan
qc carga reviews
CLIENTE=$(aws dynamodb scan --table-name "$DYNAMO_TABLE" --max-items 1 \
          --query 'Items[0].cliente.S' --output text | head -1)
aws dynamodb query --table-name "$DYNAMO_TABLE" --index-name por_cliente \
  --key-condition-expression "cliente = :c" \
  --expression-attribute-values "{\":c\":{\"S\":\"$CLIENTE\"}}" \
  --return-consumed-capacity TOTAL --output table
```

## Políticas IAM (Ex. 1.4)

`iam/*.json`: uma política por perfil. O Learner Lab não permite criar roles e políticas IAM, então elas são entregues como documento. Numa conta própria, dá para validar cada uma assim:

```bash
aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY \
  --policy-document file://$E/iam/2-lambda-le-connection-string.json
```

## N3 — busca híbrida (3.1) e benchmark (3.3)

```bash
source "$LAB/qc.sh"
qc carga catalogo && qc indexa       # cria produtos_vetor com os embeddings
pip install --quiet --no-cache-dir boto3 'psycopg[binary]' pgvector fastembed   # no venv /tmp/venv-qc

cd "$E/scripts"
python buscar_hibrido.py --saida ~/resultados-3.1.md       # 3 consultas × 3 modos
python benchmark_busca.py -n 10 --saida ~/resultados-3.3.md  # cria e APAGA uma tabela DynamoDB temporária
```

As saídas desta execução estão em `evidencias/`.

## Limpeza

```bash
cd "$LAB/terraform" && terraform destroy -var="db_password=$DB_PASSWORD" -auto-approve
aws dynamodb list-tables --query "TableNames[?starts_with(@, 'qc-aula02-bench')]"   # deve vir vazio
```

O RDS é o recurso mais caro da aula: não deixe ligado.

## Não versionar
`terraform.tfstate*`, `.terraform/`, `.env`, `*.pem`, `__pycache__/`
