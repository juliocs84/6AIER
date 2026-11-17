# Grupo 01 — Aula 03 · Como rodar o que foi entregue

Tudo no **AWS CloudShell**, com o Learner Lab iniciado. Rode **um bloco por vez**.

## 0. Preparar

```bash
export AWS_PAGER=""
cd ~ && unzip -o entrega-grupo-01-aula03.zip            # depois de Actions → Upload file
git -C ~/aie-cloud stash -q; git -C ~/aie-cloud pull -q
E=~/qc-grupo-01-aula03
LAB=~/aie-cloud/aulas/03-serverless-containers/lab
rm -rf ~/aie-cloud/aulas/0[12]*/lab/terraform/.terraform   # libera espaço do $HOME (1 GB)
```

## 1. Copiar os arquivos do grupo para dentro do lab

O Terraform usa caminhos relativos ao repositório (`modulos/`, `function/`), então ele roda dentro da pasta do lab.

```bash
cp "$E"/terraform/*.tf "$LAB/terraform/"
cp -r "$E/function/v3-frete" "$LAB/function/"
cp "$E/function/v2-s3/lambda_function.py" "$LAB/function/v2-s3/"
```

## 2. Subir: Lambda do catálogo + tool de frete + alarmes

```bash
cd "$LAB/terraform"
export PATH="$HOME/bin:$PATH" TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"; mkdir -p "$TF_PLUGIN_CACHE_DIR"
which terraform || bash ~/aie-cloud/aulas/01-fundamentos-iac/lab/install_terraform.sh
terraform init -input=false
terraform apply -auto-approve
source ../qc.sh
qc publica v2                                   # catálogo com preco_max validado
qc chama "/produtos?categoria=moveis&preco_max=1500"
curl -s "$(terraform output -raw frete_url)frete?cep_origem=01310100&cep_destino=20040002&peso_kg=2.5"; echo
```

## 3. Container no Fargate + extras de produção (3.2 e 3.4)

```bash
qc container                                    # build, push e serviço no Fargate
terraform apply -auto-approve -var="ecs_enabled=true" -var="producao_extras=true"
```

> Se o `aws_scheduler_schedule` falhar com `AccessDenied` / `iam:PassRole`, é limite do Learner Lab (a LabRole não confia no EventBridge Scheduler). O código continua sendo a entrega; registre o erro no `entrega-grupo-aula03.md` e siga.

## 4. Coletar as evidências

```bash
cd "$E/scripts"
bash evidencias.sh tudo        # 1.3 (chamadas 1 e 2), 2.2, 2.3, 3.2, 3.3 e 3.4 — ~10 min
```

Depois:

1. **Print (2.3b):** Lambda → função `qc-aula03-…-catalogo` → aba **Monitor** → capture Invocations, Duration e Errors.
2. **30 minutos depois:** `bash ~/qc-grupo-01-aula03/scripts/evidencias.sh frio3` (chamada 3 do 1.3).
3. **Ver tudo:** `tail -n +1 ~/evidencias-aula03/*.txt`

## 5. Destruir

```bash
cd "$LAB/terraform"
terraform destroy -auto-approve -var="ecs_enabled=true" -var="producao_extras=true"
aws lambda list-functions --query "Functions[?starts_with(FunctionName,'qc-aula03')].FunctionName"   # deve vir []
git -C ~/aie-cloud checkout -- . && git -C ~/aie-cloud clean -fdq aulas/03-serverless-containers   # devolve o lab ao original
```

Se tiver feito o 3.3 pelo console, apague também a `demo-estoque` e o log group `/aws/lambda/demo-estoque`: eles não estão no Terraform.

## Testes locais da tool de frete

```bash
cd ~/qc-grupo-01-aula03/function/v3-frete && python3 test_frete.py
```

## Não versionar
`terraform.tfstate*`, `.terraform/`, `.build/`, `.env`, `*.pem`, `__pycache__/`
