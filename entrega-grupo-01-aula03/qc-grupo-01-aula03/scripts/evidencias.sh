#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Coleta as evidências da Entrega 03 no CloudShell. Cada etapa grava um .txt em
# ~/evidencias-aula03/. Pré-requisito: lab da Aula 3 no ar (com os arquivos do
# grupo copiados) e o `source qc.sh` carregado.
#
#   bash evidencias.sh frio        # 1.3: chamadas 1 e 2 (fria e quente)
#   bash evidencias.sh frio3       # 1.3: chamada 3, rodar 30 min depois
#   bash evidencias.sh logs        # 2.2 + 2.3: 20+ chamadas, Logs Insights, métricas
#   bash evidencias.sh bench       # 3.2: ab na Lambda e no Fargate
#   bash evidencias.sh drift       # 3.3b: muda a memória "por fora" e roda o plan
#   bash evidencias.sh segredo     # 3.4c: o valor do segredo aparece na task definition?
#   bash evidencias.sh tudo        # frio + logs + bench + drift + segredo (sem o frio3)
# ---------------------------------------------------------------------------
set -uo pipefail
export AWS_PAGER=""
OUT="$HOME/evidencias-aula03"; mkdir -p "$OUT"
TF="${QC_LAB:-$HOME/aie-cloud/aulas/03-serverless-containers/lab}/terraform"

tfout() { terraform -chdir="$TF" output -raw "$1" 2>/dev/null; }
FUNCTION_NAME="${FUNCTION_NAME:-$(tfout lambda_name)}"
FUNCTION_URL="${FUNCTION_URL:-$(tfout function_url)}"
FRETE_URL="$(tfout frete_url)"
FRETE_NAME="$(tfout frete_lambda_name)"
ECS_CLUSTER="${ECS_CLUSTER:-$(tfout ecs_cluster_name)}"
LG="/aws/lambda/$FUNCTION_NAME"

precisa() { for v in "$@"; do [ -n "${!v:-}" ] || { echo "ERRO: $v vazio (source qc.sh? apply terminou?)" >&2; exit 1; }; done; }
agora_ms() { echo $(( $(date +%s) * 1000 )); }

# Linhas REPORT recentes do log group (mostra se houve Init Duration)
reports() {
  aws logs filter-log-events --log-group-name "$1" --start-time "$2" \
    --filter-pattern '"REPORT RequestId"' --query 'events[].message' --output text 2>/dev/null \
    | tr '\t' '\n' | sed 's/^/    /'
}

# Roda uma consulta do Logs Insights e espera o resultado
insights() {
  local lg="$1" ini="$2" q="$3" id st
  id=$(aws logs start-query --log-group-name "$lg" --start-time $(( ini / 1000 )) \
        --end-time $(( $(date +%s) + 60 )) --query-string "$q" --query queryId --output text) || return 1
  for _ in $(seq 1 30); do
    st=$(aws logs get-query-results --query-id "$id" --query status --output text)
    [ "$st" = "Complete" ] && break; sleep 2
  done
  aws logs get-query-results --query-id "$id" \
    --query 'results[0][*].[field,value]' --output text | column -t
}

chamada() {  # imprime "HTTP tempo url"
  curl -s -o /dev/null -m 30 -w "HTTP %{http_code}  %{time_total}s  $1\n" "$1"
}

etapa_frio() {
  precisa FUNCTION_NAME FUNCTION_URL
  local f="$OUT/1.3-cold-start.txt" ini
  ini=$(agora_ms)
  # Força um ambiente novo (equivale a "primeira chamada depois do deploy"): muda uma
  # variável de ambiente inócua. Sem isso, se o lab acabou de ser usado, a 1ª chamada sai quente.
  aws lambda update-function-configuration --function-name "$FUNCTION_NAME" \
    --description "cold-start-test $(date +%s)" >/dev/null && \
    aws lambda wait function-updated --function-name "$FUNCTION_NAME"
  {
    echo "== 1.3 — Cold start ($(date '+%d/%m/%Y %H:%M:%S'))"
    echo "Chamada 1 (fria):";   chamada "${FUNCTION_URL}produtos"
    sleep 5
    echo "Chamada 2 (5 s depois, quente):"; chamada "${FUNCTION_URL}produtos"
    sleep 15
    echo "Linhas REPORT do CloudWatch (a fria tem 'Init Duration'):"
    reports "$LG" "$ini"
    echo
    echo "Chamada 3: rode 'bash evidencias.sh frio3' daqui a 30 minutos."
    # devolve a descrição original para o terraform plan não acusar drift falso
    aws lambda update-function-configuration --function-name "$FUNCTION_NAME" --description "" >/dev/null
  } | tee "$f"
  date +%s > "$OUT/.frio_inicio"
}

etapa_frio3() {
  precisa FUNCTION_URL
  local f="$OUT/1.3-cold-start.txt" ini t0 min
  t0=$(cat "$OUT/.frio_inicio" 2>/dev/null || echo 0); min=$(( ($(date +%s) - t0) / 60 ))
  ini=$(agora_ms)
  {
    echo
    echo "Chamada 3 (${min} min depois da chamada 2):"; chamada "${FUNCTION_URL}produtos"
    sleep 15
    reports "$LG" "$ini"
  } | tee -a "$f"
}

etapa_logs() {
  precisa FUNCTION_NAME FUNCTION_URL FRETE_URL
  local f="$OUT/2.3-cloudwatch.txt" ini
  ini=$(agora_ms)
  {
    echo "== 2.2 — tool de frete ($(date '+%d/%m/%Y %H:%M:%S'))"
    for q in "cep_origem=01310100&cep_destino=04538133&peso_kg=2.5" \
             "cep_origem=01310-100&cep_destino=20040-002&peso_kg=2,5" \
             "cep_origem=01310100&cep_destino=90010000&peso_kg=12.2" \
             "cep_origem=123&cep_destino=20040002&peso_kg=abc"; do
      echo "GET /frete?$q"; curl -s -m 15 "${FRETE_URL}frete?$q"; echo
    done
    echo
    echo "== 2.3a — 20 chamadas variadas ao catálogo (inclui 404 e 400)"
    for c in produtos "produtos?categoria=moveis" "produtos?categoria=moveis&preco_max=1500" \
             "produtos?nome=cadeira" "produtos?categoria=eletronicos&preco_max=2000" \
             "produtos?preco_max=abc" health "produtos?categoria=calcados" \
             nao-existe "produtos?categoria=vestuario" "produtos?nome=tenis" carrinho \
             "produtos?preco_max=500" health "produtos?categoria=eletrodomesticos" \
             "produtos?nome=dell" admin "produtos?categoria=moveis&nome=gamer" \
             "produtos?preco_max=0" produtos; do
      chamada "${FUNCTION_URL}$c"
    done
    echo
    echo "Aguardando 60 s para os logs chegarem ao Logs Insights..."
    sleep 60
    echo "== Logs Insights em $LG (desde o início desta etapa)"
    insights "$LG" "$ini" 'filter @type = "REPORT"
| stats count() as chamadas, avg(@duration) as media_ms, pct(@duration, 95) as p95_ms,
        max(@maxMemoryUsed / 1000 / 1000) as memoria_mb, sum(strcontains(@message, "Init Duration")) as frias'
    echo
    echo "== Métricas (últimos 30 min, período 30 min) — complemento ao print do console"
    for m in Invocations Errors Duration; do
      st=$([ "$m" = Duration ] && echo "Average Maximum" || echo "Sum")
      echo "$m:"; aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name "$m" \
        --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
        --start-time "$(date -u -d '-30 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
        --period 1800 --statistics $st --query 'Datapoints[0]' --output json
    done
    echo
    echo "== Alarmes (2.3c)"
    aws cloudwatch describe-alarms --alarm-name-prefix "$FUNCTION_NAME" \
      --query 'MetricAlarms[].[AlarmName,StateValue,MetricName,Threshold,Period]' --output table
    aws cloudwatch describe-alarms --alarm-name-prefix "$FRETE_NAME" \
      --query 'MetricAlarms[].[AlarmName,StateValue,MetricName,Threshold,Period]' --output table
  } | tee "$f"
  echo "→ Agora tire o print: Lambda → $FUNCTION_NAME → Monitor (Invocations, Duration, Errors)."
}

ab_resumo() {  # extrai as métricas do ab
  awk '/Complete requests/{print "  requisições:", $3}
       /Failed requests/{print "  falhas:", $3}
       /Non-2xx/{print "  respostas não-2xx:", $3}
       /Requests per second/{print "  throughput (req/s):", $4}
       /Time per request.*\(mean\)$/{print "  latência média (ms):", $4}
       /^  50%/{print "  p50 (ms):", $2} /^  95%/{print "  p95 (ms):", $2}
       /^  99%/{print "  p99 (ms):", $2} /^ 100%/{print "  máx (ms):", $2}' "$1"
}

etapa_bench() {
  precisa FUNCTION_NAME FUNCTION_URL ECS_CLUSTER
  local f="$OUT/3.2-benchmark.txt" ini ip
  command -v ab >/dev/null || sudo dnf install -y -q httpd-tools >/dev/null
  ini=$(agora_ms)
  ab -r -n 1000 -c 50 -s 30 "${FUNCTION_URL}produtos?categoria=moveis" > "$OUT/ab-lambda.txt" 2>&1
  ip=$(bash "$TF/../scripts/task_ip.sh" 2>/dev/null || true)
  if [ -n "$ip" ]; then
    ab -r -n 1000 -c 50 -s 30 "http://$ip:8080/produtos?categoria=moveis" > "$OUT/ab-fargate.txt" 2>&1
  fi
  sleep 60
  {
    echo "== 3.2 — ab -n 1000 -c 50 ($(date '+%d/%m/%Y %H:%M:%S'))"
    echo "LAMBDA (${FUNCTION_URL}produtos?categoria=moveis)"; ab_resumo "$OUT/ab-lambda.txt"
    echo
    if [ -n "$ip" ]; then
      echo "FARGATE 0,25 vCPU / 0,5 GB (http://$ip:8080/produtos?categoria=moveis)"; ab_resumo "$OUT/ab-fargate.txt"
    else
      echo "FARGATE: sem tarefa rodando (rode 'qc container' e repita a etapa)"
    fi
    echo
    echo "== Lambda durante o teste (Logs Insights + métricas)"
    insights "$LG" "$ini" 'filter @type = "REPORT"
| stats count() as invocacoes, avg(@billedDuration) as billed_media_ms, pct(@duration, 95) as p95_ms,
        sum(strcontains(@message, "Init Duration")) as frias, max(@memorySize / 1000 / 1000) as memoria_mb'
    echo "ConcurrentExecutions (máximo no período):"
    aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name ConcurrentExecutions \
      --dimensions Name=FunctionName,Value="$FUNCTION_NAME" \
      --start-time "$(date -u -d '-15 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
      --period 900 --statistics Maximum --query 'Datapoints[0].Maximum' --output text
  } | tee "$f"
}

etapa_drift() {
  precisa FUNCTION_NAME
  local f="$OUT/3.3-drift.txt"
  {
    echo "== 3.3b — drift ($(date '+%d/%m/%Y %H:%M:%S'))"
    echo "Mudando a memória de $FUNCTION_NAME para 512 MB FORA do Terraform (o mesmo que o console faz)..."
    aws lambda update-function-configuration --function-name "$FUNCTION_NAME" --memory-size 512 \
      --query 'MemorySize' --output text
    aws lambda wait function-updated --function-name "$FUNCTION_NAME"
    echo
    echo "terraform plan (trecho):"
    terraform -chdir="$TF" plan -no-color -input=false -target=aws_lambda_function.catalogo 2>&1 \
      | sed -n '/Terraform will perform/,/Plan:/p'
    echo
    echo "terraform apply (restaura o que está no código):"
    terraform -chdir="$TF" apply -no-color -input=false -auto-approve -target=aws_lambda_function.catalogo 2>&1 \
      | grep -E 'Modif|Apply complete'
    echo "Memória agora: $(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --query MemorySize --output text) MB"
  } | tee "$f"
}

etapa_segredo() {
  precisa ECS_CLUSTER
  local f="$OUT/3.4-segredo.txt" td
  td=$(tfout task_definition_1vcpu)
  if [ -z "$td" ] || [ "$td" = "producao_extras = false" ]; then
    echo "Rode antes: terraform -chdir=$TF apply -var=ecs_enabled=true -var=producao_extras=true" >&2; return 1
  fi
  {
    echo "== 3.4c — o que a task definition guarda ($(date '+%d/%m/%Y %H:%M:%S'))"
    echo "environment:"
    aws ecs describe-task-definition --task-definition "$td" \
      --query 'taskDefinition.containerDefinitions[0].environment' --output table
    echo "secrets (só o ARN; o valor não aparece):"
    aws ecs describe-task-definition --task-definition "$td" \
      --query 'taskDefinition.containerDefinitions[0].secrets' --output table
    echo "cpu/memória:"
    aws ecs describe-task-definition --task-definition "$td" \
      --query 'taskDefinition.[cpu,memory]' --output text
    echo
    echo "Agendamento do job batch (3.4a):"
    aws scheduler list-schedules --name-prefix "$(tfout ecs_cluster_name | sed 's/-cluster$//')" \
      --query 'Schedules[].[Name,State]' --output table 2>&1 | head -8
    echo "Auto scaling do serviço (3.4d):"
    aws application-autoscaling describe-scaling-policies --service-namespace ecs \
      --query 'ScalingPolicies[].[PolicyName,TargetTrackingScalingPolicyConfiguration.TargetValue]' --output table 2>&1 | head -8
  } | tee "$f"
}

case "${1:-}" in
  frio) etapa_frio ;; frio3) etapa_frio3 ;; logs) etapa_logs ;; bench) etapa_bench ;;
  drift) etapa_drift ;; segredo) etapa_segredo ;;
  tudo) etapa_frio; etapa_logs; etapa_bench; etapa_drift; etapa_segredo
        echo "Falta só: 'bash evidencias.sh frio3' 30 min depois do frio." ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
echo "→ Evidências em $OUT"
