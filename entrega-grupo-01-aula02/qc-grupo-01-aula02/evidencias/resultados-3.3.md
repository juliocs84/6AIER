Pergunta: "cadeira ergonômica para dor lombar" · 10 execuções por opção · embedding da pergunta: 12.5 ms (uma vez, no cliente)

| Opção | Média (ms) | p50 (ms) | Máx (ms) | Top 3 | Trouxe o produto certo (#1) em 1º? |
|---|---|---|---|---|---|
| (a) RDS ILIKE + filtros | 1.4 | 1.3 | 2.4 | Cadeira Ergonômica DXRacer (#1) · Cadeira Gamer Vermelha (#7) · Cadeira Home Office Confortável (#14) | sim |
| (c) pgvector (sentido) | 1.5 | 1.3 | 2.5 | Cadeira Ergonômica DXRacer (#1) · Cadeira Gamer Vermelha (#7) · Cadeira Home Office Confortável (#14) | sim |
| (c') híbrido RRF (3.1) | 2.8 | 2.6 | 4.1 | Cadeira Ergonômica DXRacer (#1) · Cadeira Gamer Vermelha (#7) · Cadeira Home Office Confortável (#14) | sim |
| (b) DynamoDB Scan + contains() | 211.0 | 12.1 | 1011.1 | Cadeira Ergonômica DXRacer (#1) · Cadeira Gamer Vermelha (#7) · Cadeira Home Office Confortável (#14) | sim |

Scan do DynamoDB: leu os 20 itens da tabela para devolver 3; consumiu 2.0 RCU por execução.
