# Canvas de compute — Quantum Commerce

**Grupo:** 01 · **Entrega 03 · N2**

Uma linha por carga de trabalho. As colunas são as perguntas que decidem onde ela roda; a última é a decisão.

| Coluna | A pergunta por trás |
|--------|---------------------|
| Como é chamada | Por HTTP (o agente, o site), por evento (fila, arquivo novo) ou por agenda? |
| Quanto tempo roda | Milissegundos, minutos ou horas? (a Lambda para em 15 minutos) |
| Tráfego | Em picos, constante ou parado boa parte do dia? |
| Espera 1 s? | O usuário aguenta esperar a primeira chamada (cold start)? |
| Identidade | Com que role ela roda, e o que essa role pode ler? Só o necessário? |
| Custo/mês | Estimativa na [calculadora AWS](https://calculator.aws), região `us-east-1`, na casa escolhida e na outra |
| Onde roda e por quê | Lambda, Fargate ou outro + uma frase de justificativa (e o que vocês **não** usariam) |

## As 5 cargas da QC

Custos em preço de lista on-demand, `us-east-1`, conferíveis na [calculadora AWS](https://calculator.aws). As premissas de cada linha estão na tabela logo abaixo.

| Carga | Como é chamada | Quanto tempo roda | Tráfego | Espera 1 s? | Identidade | Custo/mês | Onde roda e por quê |
|-------|----------------|-------------------|---------|-------------|------------|-----------|---------------------|
| Busca no catálogo (`buscar_produtos`) | O agente, por HTTP | < 1 s | Picos; parada de madrugada | Sim | Só `s3:GetObject` no `catalogo/` (ver `iam/role-buscar-produtos.json`) | **Lambda ≈ US$ 0,83** · Fargate 24/7 ≈ US$ 9,01 (+ ALB) | **Lambda**: paga por chamada e parada custa zero; o cold start (~0,9 s medido no lab) só atinge a 1ª chamada após ociosidade. **Não** Fargate: pagar 24/7 para ficar parado de madrugada. |
| Cálculo de frete (`calcular_frete`) | O agente e o checkout, por HTTP | ~ms (cálculo em memória, sem I/O) | 50 mil chamadas/mês, acompanha o tráfego de compras | Sim no agente; no checkout, preferível não (ver Ex. 1.3) | **Nenhum acesso a dados**: só escrever o próprio log (`iam/role-calcular-frete.json`) | **Lambda ≈ US$ 0,02** · Fargate 24/7 ≈ US$ 9,01 | **Lambda separada** (`frete.tf`), 128 MB: função pura, barata, com role sem permissão de dados e deploy independente da busca. **Não** container: um serviço sempre ligado para 50 mil cálculos/mês é desperdício. |
| Notas fiscais (geração noturna) | Por agenda (EventBridge Scheduler, 2h) | ~1 h por noite (lote de ~330 mil NF/dia) | Uma vez por dia; parado no resto | Não (ninguém espera online) | Lê pedidos do dia (réplica de leitura do Aurora, segredo no Secrets Manager), escreve XML/PDF no `s3://…/notas/`, chama a API da SEFAZ | **Fargate (tarefa agendada) ≈ US$ 1,48** · Lambda ≈ US$ 18,48 (9,9M invocações) | **ECS Fargate RunTask agendado** (1 vCPU / 2 GB): roda 1 h e termina, paga por segundo, sem o limite de 15 min. **Não** Lambda: um lote de 1 h não cabe numa invocação, e quebrar em milhões de invocações custa mais e complica a orquestração. **Não** serviço: não precisa ficar no ar. |
| Recomendação de produtos | Treino: por agenda (noturno). Serving: o agente e a home, por HTTP | Treino: ~1 h · Serving: < 200 ms | Treino 1×/dia · Serving acompanha o tráfego, com picos | Serving: não (está na home) | Treino lê o `curated/` do lake e escreve o modelo em `s3://…/modelos/`; serving só lê o modelo e o cache de recomendações | **Treino Fargate ≈ US$ 2,96 + serving Lambda ≈ US$ 2,07** · tudo em Fargate 24/7 ≈ US$ 36 | **Duas casas:** treino em **Fargate agendado** (2 vCPU / 4 GB, `producao.tf`) e serving das recomendações **pré-calculadas** em **Lambda** com Provisioned Concurrency na home. **Não** SageMaker endpoint por enquanto: recomendações em lote cobrem o caso, e um endpoint 24/7 custa mais (Aula 5). |
| Checkout | O site e o app, por HTTP | < 1 s, mas com várias chamadas encadeadas (estoque, frete, pagamento) | Constante no horário comercial, picos fortes (Black Friday) | **Não**: cold start no pagamento derruba conversão | Escreve pedidos no Aurora (segredo injetado pelo bloco `secrets`), chama o gateway de pagamento; role sem acesso ao lake nem a outros segredos | **Fargate ≈ US$ 36 (2 tarefas 0,5 vCPU / 1 GB) + ALB ≈ US$ 16** · Lambda ≈ US$ 8 (3M req) | **ECS Fargate atrás de ALB** (HTTPS), mínimo de 2 tarefas em AZs diferentes, auto scaling por CPU (`producao.tf`): sem cold start, conexões persistentes com banco e gateway, latência estável. **Não** Lambda: o custo menor não compensa o risco de cold start e de rajada de conexões no Aurora no momento do pagamento. |

### Premissas das estimativas

| Linha | Premissa (Lambda x86: US$ 0,20/M requisições + US$ 0,0000166667/GB-s · Fargate Linux x86: US$ 0,04048/vCPU-h + US$ 0,004445/GB-h) |
|-------|------|
| Busca | 1M chamadas/mês × 150 ms × 256 MB. Fargate: 1 tarefa 0,25 vCPU / 0,5 GB × 730 h. |
| Frete | 50 mil chamadas × 50 ms (cobrança mínima; o cálculo leva ~1 ms) × 128 MB. |
| Notas fiscais | Fargate 1 vCPU / 2 GB × 1 h × 30 dias. Lambda alternativa: 9,9M invocações (1 por nota) × 200 ms × 512 MB. |
| Recomendação | Treino: Fargate 2 vCPU / 4 GB × 1 h × 30 dias. Serving: 2M chamadas × 100 ms × 512 MB (sem a Provisioned Concurrency, ≈ US$ 2,74/mês por instância de 256 MB). |
| Checkout | 2 tarefas 0,5 vCPU / 1 GB × 730 h; ALB ≈ US$ 16/mês fixo + LCUs. Lambda alternativa: 3M chamadas × 300 ms × 512 MB. |

## Uma linha do trabalho de vocês

Cada membro do grupo, uma linha com uma carga real do próprio trabalho. Anonimizem nomes, sistemas, números e clientes.

| Membro | Carga | Como é chamada | Quanto tempo roda | Tráfego | Espera 1 s? | Identidade | Custo/mês | Onde roda hoje — e onde deveria rodar |
|--------|-------|----------------|-------------------|---------|-------------|------------|-----------|---------------------------------------|
| Julio Cesar da Silva | Retreino do modelo de tendência (XGBoost) da plataforma de análise de criptoativos, e a API (FastAPI) que serve os sinais | Retreino: por agenda (diário). API: o frontend React, por HTTP | Retreino: *estimativa* de minutos. API: < 200 ms | Retreino 1×/dia. API: uso concentrado em horário de mercado, parada boa parte do tempo | API sim (painel); retreino não | Retreino lê o histórico de candles (S3) e escreve o modelo; API só lê modelo e sinais. Chave da exchange no Secrets Manager | *Estimativa:* retreino Fargate 1 vCPU / 2 GB × 15 min/dia ≈ US$ 0,40; API em Lambda < US$ 1 · tudo num container 24/7 ≈ US$ 9–36 | Hoje: backend e treino juntos no mesmo processo/servidor. Deveria: **retreino como tarefa Fargate agendada** (roda e termina) e **API em Lambda** (ou Fargate se o FastAPI precisar de conexões persistentes): o treino não disputa CPU com a API e o custo parado vai a quase zero. |
| Eduardo Oliveira Santos Cunha | Relatório diário de SLA dos chamados de suporte de um sistema interno | Por agenda (todo dia às 6h) | ~10–20 min | 1×/dia; hoje roda dentro do servidor da aplicação | Não (lido pelos gestores de manhã) | Hoje usa o mesmo usuário de banco da aplicação, com senha no arquivo de configuração; deveria ler só a réplica/histórico, com segredo no Secrets Manager | Fargate 0,5 vCPU / 1 GB × 20 min/dia ≈ US$ 0,25 · servidor dedicado 24/7 ≈ US$ 15–30 | Hoje: cron no próprio servidor da aplicação, competindo com o atendimento. Deveria: **tarefa Fargate agendada pelo EventBridge Scheduler**, lendo do histórico (S3 + Athena da Aula 2), com role própria só de leitura. **Não** Lambda se o relatório passar de 15 min. |
