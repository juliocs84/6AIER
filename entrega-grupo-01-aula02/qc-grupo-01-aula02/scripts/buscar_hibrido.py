"""
Aula 2 / Exercício 3.1 — Busca HÍBRIDA (palavra + significado) no mesmo PostgreSQL.

Para cada consulta roda três modos e mostra o top 3 de cada:
  1. PALAVRA  — full-text em português (tsvector + GIN, ts_rank)
  2. VETOR    — pgvector, distância de cosseno sobre os embeddings do `qc indexa`
  3. HÍBRIDO  — Reciprocal Rank Fusion dos dois rankings: score = Σ 1/(60 + posição)

Pré-requisitos (no CloudShell, com o lab da Aula 2 no ar):
    source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh
    qc indexa                       # cria produtos_vetor com os embeddings

Uso:
    python buscar_hibrido.py                          # as 3 consultas do exercício
    python buscar_hibrido.py "Dell Inspiron" "..."    # consultas próprias
    python buscar_hibrido.py --saida resultados-3.1.md

O script garante sozinho a coluna `tsv` e o índice GIN (idempotente): o
`qc indexa` recria a tabela do zero, então rodar o ALTER uma única vez não basta.

Variável de ambiente: SECRET_ID (o `source qc.sh` exporta).
"""

import argparse
import os
import sys

import boto3
import psycopg
from fastembed import TextEmbedding
from pgvector.psycopg import register_vector

MODELO = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"  # o mesmo do qc indexa
CACHE_MODELO = os.environ.get("FASTEMBED_CACHE", "/tmp/fastembed")       # $HOME tem só 1 GB
K_RRF = 60       # constante do RRF (valor do artigo original de Cormack et al., 2009)
PROFUNDIDADE = 10  # quantos candidatos cada busca entrega para a fusão
TOP = 3

CONSULTAS_PADRAO = [
    "Dell Inspiron",
    "algo para trabalhar em pé",
    "presente para quem gosta de correr",
]

DDL_FULLTEXT = [
    """ALTER TABLE produtos_vetor
         ADD COLUMN IF NOT EXISTS tsv tsvector
         GENERATED ALWAYS AS (to_tsvector('portuguese', nome || ' ' || coalesce(descricao, ''))) STORED""",
    "CREATE INDEX IF NOT EXISTS produtos_tsv ON produtos_vetor USING gin (tsv)",
]

SQL_PALAVRA = """
    SELECT id, ts_rank(tsv, plainto_tsquery('portuguese', %s)) AS r
    FROM produtos_vetor
    WHERE tsv @@ plainto_tsquery('portuguese', %s)
    ORDER BY r DESC, id
    LIMIT %s
"""

SQL_VETOR = """
    SELECT id, embedding <=> %s AS distancia
    FROM produtos_vetor
    ORDER BY distancia, id
    LIMIT %s
"""


def connection_string():
    secret_id = os.environ.get("SECRET_ID") or sys.exit(
        "SECRET_ID vazio. Rode: source ~/aie-cloud/aulas/02-storage-bancos/lab/qc.sh")
    return boto3.client("secretsmanager").get_secret_value(SecretId=secret_id)["SecretString"]


def rrf(*rankings, k=K_RRF):
    """Funde listas de ids ordenadas. Posição começa em 1. Desempate pelo id."""
    score = {}
    for ranking in rankings:
        for posicao, pid in enumerate(ranking, start=1):
            score[pid] = score.get(pid, 0.0) + 1.0 / (k + posicao)
    return sorted(score.items(), key=lambda kv: (-kv[1], kv[0]))


def buscar(conn, modelo, consulta):
    palavra = [pid for pid, _ in conn.execute(SQL_PALAVRA, (consulta, consulta, PROFUNDIDADE))]
    vetor_q = next(modelo.embed([consulta]))
    vetor = [pid for pid, _ in conn.execute(SQL_VETOR, (vetor_q, PROFUNDIDADE))]
    hibrido = [pid for pid, _ in rrf(palavra, vetor)]
    return {"palavra": palavra[:TOP], "vetor": vetor[:TOP], "hibrido": hibrido[:TOP]}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("consultas", nargs="*", default=CONSULTAS_PADRAO)
    ap.add_argument("--saida", help="grava a tabela de resultados em Markdown neste arquivo")
    args = ap.parse_args()

    with psycopg.connect(connection_string(), connect_timeout=15, autocommit=True) as conn:
        if not conn.execute("SELECT to_regclass('produtos_vetor')").fetchone()[0]:
            sys.exit("A tabela produtos_vetor não existe. Rode antes: qc indexa")
        for ddl in DDL_FULLTEXT:
            conn.execute(ddl)
        register_vector(conn)
        nomes = dict(conn.execute("SELECT id, nome FROM produtos_vetor").fetchall())

        modelo = TextEmbedding(model_name=MODELO, cache_dir=CACHE_MODELO)

        linhas_md = ["| Consulta | Modo | Top 1 | Top 2 | Top 3 |", "|---|---|---|---|---|"]
        for consulta in args.consultas:
            res = buscar(conn, modelo, consulta)
            print(f'\nConsulta: "{consulta}"')
            for modo in ("palavra", "vetor", "hibrido"):
                ids = res[modo]
                rotulos = [f"{nomes[i]} (#{i})" for i in ids] or ["(nenhum resultado)"]
                print(f"  {modo:<8} → " + " | ".join(rotulos))
                cel = rotulos + ["—"] * (TOP - len(rotulos))
                linhas_md.append(f'| "{consulta}" | {modo} | ' + " | ".join(cel[:TOP]) + " |")

    if args.saida:
        with open(args.saida, "w", encoding="utf-8") as f:
            f.write("\n".join(linhas_md) + "\n")
        print(f"\n✓ Tabela gravada em {args.saida}")


if __name__ == "__main__":
    main()
