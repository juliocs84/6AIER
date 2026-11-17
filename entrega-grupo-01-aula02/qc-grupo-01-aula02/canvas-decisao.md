# Canvas de decisão de dados — Quantum Commerce

**Grupo:** 01 · **Entrega 02 · N2**

Uma linha por dado. As colunas são as perguntas que decidem onde ele mora; a última é a decisão.

| Coluna | A pergunta por trás |
|--------|---------------------|
| Que pergunta responde | O que o agente, o cliente ou o time pergunta a esse dado? |
| Volume e crescimento | Quanto é hoje, e quanto cresce por mês? |
| Pode errar? | Pode ficar desatualizado por um minuto, ou envolve dinheiro? |
| Quem lê / credencial | Quem acessa, e onde fica a senha ou a role? |
| Custo/mês | Estimativa na [calculadora AWS](https://calculator.aws), região `us-east-1` |
| Onde mora e por quê | Serviço AWS + uma frase de justificativa (e o que vocês **não** usariam) |

## Os 9 domínios da QC

Volumes do [Exercício 2.1](../../aulas/02-storage-bancos/exercicios.md). Custos em preço de lista on-demand, `us-east-1`, conferíveis na [calculadora AWS](https://calculator.aws). As premissas de cada linha estão na tabela logo abaixo.

| Dado | Que pergunta responde | Volume e crescimento | Pode errar? | Quem lê / credencial | Custo/mês | Onde mora e por quê |
|------|-----------------------|----------------------|-------------|----------------------|-----------|---------------------|
| Reviews | O que os clientes acham deste produto? E o que este cliente já avaliou? | ~30M textos (~30 GB), +~1M/mês | Sim (minutos) | Agente de atendimento e frontend, pela role da função (só `dynamodb:Query` na tabela e no GSI) | ≈ US$ 25 | **DynamoDB on-demand**, PK `produto_id` + SK `review_id`, GSI `por_cliente`: sempre lido por produto ou por cliente, nunca com join. **Não** RDS: texto livre sem schema e 30M linhas que só crescem. |
| Produtos (5M SKUs) | Qual o preço e o estoque deste SKU? Quais produtos desta categoria? | 5M linhas (~50 GB) + 50 TB de imagens; cresce pouco | Preço e estoque: **não** (vira pedido) | Frontend, agentes e ETL de catálogo; connection string no Secrets Manager, lida pela role | ≈ US$ 445 (banco) + US$ 1.178 (imagens) | **Aurora PostgreSQL** (catálogo) + **S3/CloudFront** para imagens: esquema fixo, joins com categoria e estoque com integridade. **Não** DynamoDB: o catálogo precisa de filtro e ordenação por vários campos. |
| Clientes (~50M) | Quem é este cliente, onde ele mora, o que ele prefere? | ~50M perfis (~100 GB), +~1%/mês | Não para endereço e consentimento (LGPD) | Pedidos, atendimento, marketing (só colunas permitidas); Secrets Manager + role por serviço | ≈ US$ 360 (1/3 do cluster transacional) | **Aurora PostgreSQL** (mesmo cluster de Pedidos): integridade referencial com pedidos e controle fino por coluna para dado pessoal. **Não** DynamoDB: o perfil é consultado em joins de faturamento. |
| Pedidos (~10M/mês) | Quanto este cliente pagou, e o pedido foi faturado? | ~20 GB/mês, histórico de anos | **Nunca** (dinheiro, nota fiscal) | Checkout, faturamento, financeiro; role com escrita só para o checkout | ≈ US$ 730 (2/3 do cluster transacional) | **Aurora PostgreSQL Multi-AZ**: ACID, transação que debita estoque e cria o pedido na mesma operação. O histórico antigo vai para o lake (S3) via DMS CDC. |
| Carrinhos ativos (~500k) | O que este cliente está prestes a comprar? | ~500k vivos, ~2 GB, rotação diária | Sim (segundos) | Frontend, pela role da API | ≈ US$ 245 | **DynamoDB on-demand** com **TTL de 24 h**: acesso por `cliente_id`, item de esquema variável que expira sozinho. **Não** RDS: limpar 500k linhas por dia é job e lock à toa. |
| Busca de produtos | "Algo para trabalhar em pé" e "Dell Inspiron 15" na mesma caixa | Índice de 5M SKUs (~60 GB com vetores), reindexação contínua | Sim (minutos de atraso na indexação) | Agentes e frontend; role só de leitura no índice | ≈ US$ 700 | **OpenSearch Serverless** (busca híbrida BM25 + k-NN, facetas, sinônimos), alimentado por CDC do catálogo. O pgvector do lab serve para protótipo e catálogos pequenos (ver Ex. 3.1). |
| Sessões (~1M) | Este usuário está logado? Qual o contexto da navegação? | ~1M × 2 KB = 2 GB, TTL 30 min | Sim (refaz login) | API, pela role; sem credencial no código (IAM auth) | ≈ US$ 135 | **ElastiCache Serverless (Valkey)**: latência sub-ms em toda requisição. DynamoDB com TTL seria a alternativa mais barata se 5–10 ms bastassem. |
| Histórico de navegação | O que os clientes veem antes de comprar? Qual funil converte? | Bilhões de eventos: ~3 bi/mês ≈ 1,4 TB/mês bruto | Sim (análise em lote) | Analistas (Athena), time de ML; Lake Formation por camada | ≈ US$ 107 (1º ano, cresce com o acúmulo) | **Data Firehose → S3 (Parquet particionado) + Athena**: grava barato e consulta sob demanda. **Não** banco operacional: ninguém consulta um clique isolado em tempo real. |
| Modelos de ML | Qual versão do modelo de recomendação está em produção, e com que dados foi treinada? | ~200 GB de artefatos, cresce por versão | Não (precisa reproduzir a versão exata) | Pipeline de treino (escreve), endpoint de inferência (lê); roles distintas | ≈ US$ 5 (armazenamento; o serving é custo da Aula 5) | **S3 versionado + SageMaker Model Registry**: artefato imutável por versão, com linhagem. **Não** banco: `.pkl` é objeto, não linha. |
| **Total da camada de dados** | | | | | **≈ US$ 3.930/mês** | |

### Premissas das estimativas

| Linha | Premissa (preço de lista on-demand, `us-east-1`) |
|-------|--------------------------------------------------|
| Produtos | 2 × Aurora PostgreSQL `db.r6g.large` (writer + reader, ≈ US$ 190/mês cada) + 50 GB a US$ 0,10 + 300M de I/O a US$ 0,20/M = **US$ 445**. Imagens: 51.200 GB × US$ 0,023 = **US$ 1.177,60** (sem CloudFront). |
| Clientes + Pedidos | Cluster `db.r6g.xlarge` writer + reader (≈ US$ 379/mês cada) + 340 GB (100 GB de clientes + 12 meses × 20 GB de pedidos) + 1.500M de I/O = **US$ 1.092**, rateado 1/3 para Clientes e 2/3 para Pedidos. |
| Carrinhos | 500k carrinhos novos/dia × 20 gravações = 300M WRU × US$ 0,625/M; 60 leituras eventuais (0,5 RRU) = 450M RRU × US$ 0,125/M; 2 GB × US$ 0,25. |
| Reviews | 1M de reviews novas/mês × 2 WRU (tabela + GSI); 200M de leituras eventuais = 100M RRU; 30 GB × 1,5 (GSI com projeção parcial) × US$ 0,25. |
| Busca | OpenSearch Serverless: 2 OCU de indexação + 2 OCU de busca (com réplica) × US$ 0,24/OCU-h × 730 h + 60 GB × US$ 0,024. |
| Sessões | ElastiCache Serverless Valkey: 2 GB × US$ 0,084/GB-h × 730 h + 2.000 req/s × 1 ECPU × US$ 0,0023/M ECPU. |
| Histórico de navegação | 3 bi eventos × 0,5 KB = 1.430 GB/mês × (US$ 0,029 de ingestão + US$ 0,018 de conversão para Parquet), com eventos agregados em registros ≥ 5 KB (o Firehose cobra em incrementos de 5 KB); Parquet ~5× menor, acúmulo médio de 6 meses no 1º ano. |
| Modelos de ML | 200 GB × US$ 0,023. |

## Uma linha do trabalho de vocês

Cada membro do grupo, uma linha com um dado real do próprio trabalho. Anonimizem nomes, números e clientes.

| Membro | Dado | Que pergunta responde | Volume e crescimento | Pode errar? | Quem lê / credencial | Custo/mês | Onde mora hoje — e onde deveria morar |
|--------|------|-----------------------|----------------------|-------------|----------------------|-----------|---------------------------------------|
| Julio Cesar da Silva | Séries de candles (OHLCV) de criptoativos e os sinais do modelo de tendência (XGBoost) da plataforma de análise | "Qual a tendência deste ativo neste timeframe, e o que o modelo previu?" | *Estimativa:* ~30 ativos × 3 timeframes (1h, 4h, 1d) × ~4 anos ≈ 1,4M candles ≈ **~80 MB**; cresce ~2 MB/mês | Candles históricos: não (o modelo treina neles). Sinal do dia: pode atrasar minutos | Backend FastAPI (leitura) e job de treino (escrita); a chave de API da exchange fica na configuração do backend | Hoje ≈ US$ 0 (fica junto do backend). Na AWS: S3 Parquet < US$ 0,01 + DynamoDB on-demand < US$ 1 | Hoje: junto do backend da plataforma. Deveria: candles em **S3 Parquet particionado por ativo/ano** (treino e backtest via Athena ou pandas), sinais recentes em **DynamoDB** (PK `ativo`, SK `timestamp`, TTL 30 dias) para a API, e a chave da exchange no **Secrets Manager**. A lição do canvas: o volume é pequeno e o que decide é o padrão de leitura (lote × por chave), não o tamanho. |
| Eduardo Oliveira Santos Cunha | *Exemplo ilustrativo — substituir por um dado real do trabalho:* chamados de suporte de um sistema interno | "Quais chamados estão abertos há mais de 48 h, e qual é o tempo médio de resolução por equipe?" | ~5 mil chamados/mês, ~2 KB cada (~10 MB/mês), histórico de alguns anos | Status do chamado: pode atrasar minutos. Relatório de SLA: não pode errar (vira meta de equipe) | Analistas de suporte e gestores; senha do banco no arquivo de configuração da aplicação | Hoje: rateado no servidor do sistema. Na AWS: RDS `db.t4g.micro` ≈ US$ 12 | Hoje: banco relacional do próprio sistema, com relatórios rodando direto nele. Deveria: operação no **RDS PostgreSQL** (com a senha no **Secrets Manager**) e histórico exportado para **S3 + Athena**, para os relatórios de SLA não competirem com o atendimento. |
