"""
Lambda HTTP da Quantum Commerce — tool `calcular_frete` (Exercício 2.2).

Segunda tool consumida pelos agentes. Função PURA e determinística:
não lê S3, banco nem segredo. Por isso roda numa função separada, com uma
execution role que não precisa de permissão nenhuma além de escrever log.

Rotas (Function URL própria):
    GET /frete?cep_origem=01310100&cep_destino=20040002&peso_kg=2.5
    GET /health

Regra de preço (tabela fictícia da QC, em R$):
    valor = BASE[tipo_de_rota] + POR_KG[tipo_de_rota] × peso_cobrado
    peso_cobrado = peso arredondado para cima em múltiplos de 0,5 kg (mínimo 0,5 kg)

    tipo_de_rota, pela região do 1º dígito do CEP (faixas dos Correios):
        "local"     → mesma faixa de CEP (mesmo 1º dígito)
        "regional"  → faixas diferentes na mesma macrorregião
        "nacional"  → macrorregiões diferentes
"""
import json
import logging
import math

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 1º dígito do CEP → (faixa, macrorregião)
FAIXAS = {
    "0": ("SP capital e Grande SP", "SUDESTE"),
    "1": ("interior de SP", "SUDESTE"),
    "2": ("RJ e ES", "SUDESTE"),
    "3": ("MG", "SUDESTE"),
    "4": ("BA e SE", "NORDESTE"),
    "5": ("PE, AL, PB e RN", "NORDESTE"),
    "6": ("CE, PI, MA e Norte", "NORTE_NORDESTE"),
    "7": ("DF, GO, TO, MT, MS, RO, AC", "CENTRO_OESTE"),
    "8": ("PR e SC", "SUL"),
    "9": ("RS", "SUL"),
}

TABELA = {          # base R$, R$ por kg, prazo base (dias úteis)
    "local":    (12.00, 1.50, 2),
    "regional": (18.00, 2.50, 4),
    "nacional": (25.00, 4.00, 7),
}
PESO_MAX_KG = 30.0
PRAZO_EXTRA_PESADO = 2   # acima de 10 kg: transportadora, +2 dias úteis


def resposta(corpo: dict, status: int = 200) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json; charset=utf-8"},
        "body": json.dumps(corpo, ensure_ascii=False),
    }


def normalizar_cep(valor: str | None) -> str | None:
    digitos = "".join(c for c in (valor or "") if c.isdigit())
    return digitos if len(digitos) == 8 else None


def calcular_frete(cep_origem: str, cep_destino: str, peso_kg: float) -> dict:
    """Lógica de negócio, sem nada de HTTP: testável e reaproveitável."""
    faixa_o, regiao_o = FAIXAS[cep_origem[0]]
    faixa_d, regiao_d = FAIXAS[cep_destino[0]]
    if cep_origem[0] == cep_destino[0]:
        rota = "local"
    elif regiao_o == regiao_d:
        rota = "regional"
    else:
        rota = "nacional"

    peso_cobrado = max(0.5, math.ceil(peso_kg * 2) / 2)
    base, por_kg, prazo = TABELA[rota]
    valor = round(base + por_kg * peso_cobrado, 2)
    if peso_kg > 10:
        prazo += PRAZO_EXTRA_PESADO

    return {
        "valor_reais": valor,
        "prazo_dias_uteis": prazo,
        "tipo_rota": rota,
        "origem": {"cep": cep_origem, "faixa": faixa_o},
        "destino": {"cep": cep_destino, "faixa": faixa_d},
        "peso_informado_kg": peso_kg,
        "peso_cobrado_kg": peso_cobrado,
        "memoria_de_calculo": f"R$ {base:.2f} + R$ {por_kg:.2f}/kg × {peso_cobrado} kg",
    }


def rota_frete(params: dict) -> dict:
    cep_o = normalizar_cep(params.get("cep_origem"))
    cep_d = normalizar_cep(params.get("cep_destino"))
    erros = []
    if not cep_o:
        erros.append("cep_origem deve ter 8 dígitos (ex.: 01310100 ou 01310-100)")
    if not cep_d:
        erros.append("cep_destino deve ter 8 dígitos (ex.: 20040002 ou 20040-002)")
    try:
        peso = float((params.get("peso_kg") or "").replace(",", "."))
        if not 0 < peso <= PESO_MAX_KG:
            erros.append(f"peso_kg deve estar entre 0 e {PESO_MAX_KG:g} kg")
    except ValueError:
        erros.append("peso_kg deve ser um número em kg (ex.: 2.5)")
    if erros:
        # 400 com mensagens claras: o agente consegue corrigir e tentar de novo
        return resposta({"erro": "parâmetros inválidos", "detalhes": erros}, 400)

    resultado = calcular_frete(cep_o, cep_d, peso)
    logger.info(json.dumps({"evento": "frete_calculado", "tipo_rota": resultado["tipo_rota"],
                            "peso_cobrado_kg": resultado["peso_cobrado_kg"],
                            "valor_reais": resultado["valor_reais"]}))
    return resposta(resultado)


def lambda_handler(event, context):
    caminho = event.get("rawPath", "/")
    params = event.get("queryStringParameters") or {}
    if caminho == "/health":
        return resposta({"status": "ok", "service": "qc-frete"})
    if caminho in ("/", "/frete"):
        return rota_frete(params)
    return resposta({"erro": f"rota {caminho} não existe", "rotas": ["/frete", "/health"]}, 404)
