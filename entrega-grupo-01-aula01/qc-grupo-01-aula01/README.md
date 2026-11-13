# Grupo 01 — Aula 01 · Como rodar o N3

Tudo no **AWS CloudShell** (política "no install"). Pré-requisitos:

```bash
export AWS_PAGER=""          # evita que a AWS CLI abra o "less" e engula os comandos seguintes
cd ~ && unzip -o entrega-grupo-01-aula01.zip          # após Actions → Upload file
git clone https://github.com/IsaiasBritto/aie-cloud-aws.git ~/aie-cloud   # lab original
which terraform || bash ~/aie-cloud/aulas/01-fundamentos-iac/lab/install_terraform.sh
[ -f ~/.ssh/id_rsa.pub ] || ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
```

## 3.1 — Terraform (SG endurecido, update in-place)

O diff só aparece como *update in-place* se o lab original estiver aplicado **na mesma pasta** (mesmo state).

```bash
mkdir -p ~/aula01-tf && cd ~/aula01-tf

# 1) lab original (SSH aberto)
cp ~/aie-cloud/aulas/01-fundamentos-iac/lab/terraform/{main.tf,variables.tf,outputs.tf} .
terraform init
terraform apply -auto-approve

# 2) versão endurecida, mesma pasta
cp ~/qc-grupo-01-aula01/terraform/{main.tf,variables.tf,outputs.tf} .
export MEU_IP=$(curl -s https://checkip.amazonaws.com)
terraform plan -no-color -var="meu_ip=${MEU_IP}" -out=tfplan | tee ~/plan-3.1.txt
#    esperado: Plan: 3 to add, 1 to change, 0 to destroy.
terraform apply tfplan | tee ~/apply-3.1.txt
#    esperado: Apply complete! Resources: 3 added, 1 changed, 0 destroyed.
terraform output

# negativo: a validação deve barrar
terraform plan -var="meu_ip=0.0.0.0"

# 3) limpeza
terraform destroy -var="meu_ip=${MEU_IP}" -auto-approve
```

## 3.2 — CloudFormation

Rode **um bloco por vez**.

```bash
mkdir -p ~/aula01-cfn
cp ~/qc-grupo-01-aula01/cloudformation/template.yaml ~/aula01-cfn/
cd ~/aula01-cfn
aws cloudformation validate-template --template-body file://template.yaml
```

```bash
aws cloudformation deploy \
  --stack-name aula01-grupo \
  --template-file template.yaml \
  --parameter-overrides SshCidr="$(curl -s https://checkip.amazonaws.com)/32"
aws cloudformation describe-stacks --stack-name aula01-grupo --query "Stacks[0].Outputs" --output table
wc -l ~/aula01-tf/main.tf ~/aula01-cfn/template.yaml
```

Drift: termine a EC2 fora do CloudFormation (console, ou `aws ec2 terminate-instances --instance-ids <InstanceId>`), depois:

```bash
DRIFT_ID=$(aws cloudformation detect-stack-drift --stack-name aula01-grupo --query StackDriftDetectionId --output text)
sleep 30
aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id "$DRIFT_ID" \
  --query "{Status:DetectionStatus,Drift:StackDriftStatus,Recursos:DriftedStackResourceCount}" --output table
aws cloudformation describe-stack-resource-drifts --stack-name aula01-grupo \
  --query "StackResourceDrifts[].{Recurso:LogicalResourceId,Status:StackResourceDriftStatus}" --output table
```

```bash
aws cloudformation delete-stack --stack-name aula01-grupo
aws cloudformation wait stack-delete-complete --stack-name aula01-grupo && echo "STACK REMOVIDA"
```

> O `wait stack-delete-complete` também retorna sucesso se a stack nunca existiu. Confirme com `describe-stacks` antes de concluir que algo foi apagado.

## Não versionar
`terraform.tfstate*`, `.terraform/`, `tfplan`, `terraform.tfvars`, `*.pem`, `.env`
