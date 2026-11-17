"""
Aula 2 / Exercício 3.3 — Benchmark: RDS (ILIKE) × DynamoDB (Scan) × pgvector (× híbrido).

Pergunta do agente: "cadeira ergonômica para dor lombar".
Mede a latência de N execuções de cada opção, mostra o top 3 e as unidades
de leitura consumidas pelo Scan do DynamoDB.

  (a) RDS PostgreSQL: ILIKE '%cadeira%' + filtros de categoria e preço
  (b) DynamoDB: Scan com contains() — cria uma tabela temporária com os 20
      produtos do catálogo (PAY_PER_REQUEST) e APAGA no final
  (c) pgvector: busca por significado (e a híbrida do 3.1, para comparação)

Pré-requisitos: lab da Aula 2 no ar, `source qc.sh` e `qc indexa`.

Uso:
    python benchmark_busca.py                 # 10 execuções por opção
    python benchmark_busca.py -n 20 --saida resultados-3.3.md
    python benchmark_busca.py --sem-dynamo    # pula a opção (b)

Variáveis de ambiente: SECRET_ID e BUCKET_NAME (o `source qc.sh` exporta).
"""

import argparse
import csv
import os
import statistics
import sys
import time
from decimal import Decimal

import boto3
import psycopg
from fastembed import TextEmbedding
from pgvector.psycopg import register_vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from buscar_hibrido import CACHE_MODELO, DDL_FULLTEXT, MODELO, connection_string, rrf  # noqa: E402

PERGUNTA = "cadeira ergonômica para dor lombar"
ESPERADO = 1  # Cadeira Ergonômica DXRacer — a única com "apoio lombar" na descrição

SQL_ILIKE = """
    SELECT id FROM produtos_vetor
    WHERE (nome ILIKE %s OR descricao ILIKE %s)
      AND categoria = %s AND preco <= %s
    ORDER BY preco DESC, id
    LIMIT 3
"""
SQL_VETOR = "SELECT id FROM produtos_vetor ORDER BY embedding <=> %s, id LIMIT %s"
SQL_PALAVRA = """
    SELECT id FROM produtos_vetor WHERE tsv @@ plainto_tsquery('portuguese', %s)
    ORDER BY ts_rank(tsv, plainto_tsquery('portuguese', %s)) DESC, id LIMIT %s
"""


def cronometra(fn, n):
    tempos, resultado = [], None
    for _ in range(n):
        t0 = time.perf_counter()
        resultado = fn()
        tempos.append((time.perf_counter() - t0) * 1000)
    return resultado, tempos


def resumo(tempos):
    return {
        "media": statistics.mean(tempos),
        "p50": statistics.median(tempos),
        "max": max(tempos),
    }


def dynamo_scan(n):
    """Cria tabela temporária, carrega os produtos, mede o Scan e apaga a tabela."""
    bucket = os.environ.get("BUCKET_NAME") or sys.exit("Exporte BUCKET_NAME (source qc.sh).")
    corpo = boto3.client("s3").get_object(Bucket=bucket, Key="catalogo/produtos.csv")["Body"]
    rows = list(csv.DictReader(corpo.read().decode("utf-8").splitlines()))

    ddb = boto3.resource("dynamodb")
    nome = f"qc-aula02-bench-{int(time.time())}"
    print(f"→ DynamoDB: criando tabela temporária {nome}...")
    tabela = ddb.create_table(
        TableName=nome,
        KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
        AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "N"}],
        BillingMode="PAY_PER_REQUEST",
        Tags=[{"Key": "aula", "Value": "2"}, {"Key": "projeto", "Value": "quantum-commerce"}],
    )
    try:
        tabela.wait_until_exists()
        with tabela.batch_writer() as bw:
            for r in rows:
                bw.put_item(Item={
                    "id": int(r["id"]), "nome": r["nome"], "descricao": r["descricao"],
                    "categoria": r["categoria"], "preco": Decimal(r["preco"]),
                    # contains() diferencia maiúsculas: sem uma cópia em minúsculas,
                    # "cadeira" não casa com "Cadeira"
                    "texto_lc": f"{r['nome']} {r['descricao']}".lower(),
                })

        from boto3.dynamodb.conditions import Attr
        filtro = (Attr("texto_lc").contains("cadeira") & Attr("categoria").eq("moveis")
                  & Attr("preco").lte(Decimal("2000")))
        consumo = {}

        def scan():
            itens, kwargs, rcu = [], {"FilterExpression": filtro, "ReturnConsumedCapacity": "TOTAL"}, 0.0
            while True:  # Scan pagina de 1 MB em 1 MB: lê a tabela INTEIRA
                resp = tabela.scan(**kwargs)
                itens += resp["Items"]
                rcu += resp["ConsumedCapacity"]["CapacityUnits"]
                if "LastEvaluatedKey" not in resp:
                    break
                kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
            consumo["rcu"] = rcu
            consumo["lidos"] = len(rows)
            ordenados = sorted(itens, key=lambda i: (-float(i["preco"]), int(i["id"])))
            return [int(i["id"]) for i in ordenados[:3]]

        ids, tempos = cronometra(scan, n)
        return ids, tempos, consumo
    finally:
        print(f"→ DynamoDB: apagando {nome}")
        tabela.delete()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=10, help="execuções por opção (padrão 10)")
    ap.add_argument("--saida", help="grava a tabela comparativa em Markdown")
    ap.add_argument("--sem-dynamo", action="store_true")
    args = ap.parse_args()

    resultados = {}
    with psycopg.connect(connection_string(), connect_timeout=15, autocommit=True) as conn:
        if not conn.execute("SELECT to_regclass('produtos_vetor')").fetchone()[0]:
            sys.exit("A tabela produtos_vetor não existe. Rode antes: qc indexa")
        for ddl in DDL_FULLTEXT:
            conn.execute(ddl)
        register_vector(conn)
        nomes = dict(conn.execute("SELECT id, nome FROM produtos_vetor").fetchall())

        # (a) ILIKE + filtros
        def ilike():
            return [r[0] for r in conn.execute(SQL_ILIKE, ("%cadeira%", "%cadeira%", "moveis", 2000))]
        ilike()  # aquecimento (conexão e plano)
        resultados["(a) RDS ILIKE + filtros"] = cronometra(ilike, args.n)

        # (c) pgvector — o embedding da pergunta é gerado UMA vez (custo à parte)
        modelo = TextEmbedding(model_name=MODELO, cache_dir=CACHE_MODELO)
        next(modelo.embed(["aquecimento"]))
        t0 = time.perf_counter()
        vetor_q = next(modelo.embed([PERGUNTA]))
        t_embed = (time.perf_counter() - t0) * 1000

        def vetor():
            return [r[0] for r in conn.execute(SQL_VETOR, (vetor_q, 3))]
        vetor()
        resultados["(c) pgvector (sentido)"] = cronometra(vetor, args.n)

        def hibrido():
            p = [r[0] for r in conn.execute(SQL_PALAVRA, (PERGUNTA, PERGUNTA, 10))]
            v = [r[0] for r in conn.execute(SQL_VETOR, (vetor_q, 10))]
            return [pid for pid, _ in rrf(p, v)][:3]
        hibrido()
        resultados["(c') híbrido RRF (3.1)"] = cronometra(hibrido, args.n)

    consumo = None
    if not args.sem_dynamo:
        ids, tempos, consumo = dynamo_scan(args.n)
        resultados["(b) DynamoDB Scan + contains()"] = (ids, tempos)

    linhas = [
        f'Pergunta: "{PERGUNTA}" · {args.n} execuções por opção · '
        f"embedding da pergunta: {t_embed:.1f} ms (uma vez, no cliente)",
        "",
        "| Opção | Média (ms) | p50 (ms) | Máx (ms) | Top 3 | Trouxe o produto certo (#1) em 1º? |",
        "|---|---|---|---|---|---|",
    ]
    for opcao, (ids, tempos) in resultados.items():
        s = resumo(tempos)
        top = " · ".join(f"{nomes.get(i, i)} (#{i})" for i in ids) or "(nenhum)"
        certo = "sim" if ids and ids[0] == ESPERADO else ("não (aparece)" if ESPERADO in ids else "não")
        linhas.append(f"| {opcao} | {s['media']:.1f} | {s['p50']:.1f} | {s['max']:.1f} | {top} | {certo} |")
    if consumo:
        linhas += ["", f"Scan do DynamoDB: leu os {consumo['lidos']} itens da tabela para devolver "
                   f"{len(resultados['(b) DynamoDB Scan + contains()'][0])}; "
                   f"consumiu {consumo['rcu']:.1f} RCU por execução."]

    print("\n" + "\n".join(linhas))
    if args.saida:
        with open(args.saida, "w", encoding="utf-8") as f:
            f.write("\n".join(linhas) + "\n")
        print(f"\n✓ Tabela gravada em {args.saida}")


if __name__ == "__main__":
    main()
