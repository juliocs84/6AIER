"""Testes da tool de frete. Rodar: python -m pytest -q test_frete.py (ou python test_frete.py)."""
import json

from lambda_function import calcular_frete, lambda_handler


def chamar(path="/frete", **params):
    r = lambda_handler({"rawPath": path, "queryStringParameters": params or None}, None)
    return r["statusCode"], json.loads(r["body"])


def test_local():
    r = calcular_frete("01310100", "04538133", 2.5)          # SP capital → SP capital
    assert (r["tipo_rota"], r["valor_reais"], r["prazo_dias_uteis"]) == ("local", 15.75, 2)


def test_regional():
    r = calcular_frete("01310100", "20040002", 2.5)          # SP → RJ (ambos Sudeste)
    assert (r["tipo_rota"], r["valor_reais"], r["prazo_dias_uteis"]) == ("regional", 24.25, 4)


def test_nacional_pesado():
    r = calcular_frete("01310100", "90010000", 12.2)         # SP → RS, 12,2 kg → cobra 12,5 kg
    assert r["tipo_rota"] == "nacional" and r["peso_cobrado_kg"] == 12.5
    assert r["valor_reais"] == 75.0 and r["prazo_dias_uteis"] == 9


def test_peso_minimo_e_arredondamento():
    assert calcular_frete("01310100", "01310100", 0.1)["peso_cobrado_kg"] == 0.5
    assert calcular_frete("01310100", "01310100", 1.01)["peso_cobrado_kg"] == 1.5


def test_http_ok_com_cep_formatado_e_virgula():
    st, b = chamar(cep_origem="01310-100", cep_destino="20040-002", peso_kg="2,5")
    assert st == 200 and b["valor_reais"] == 24.25


def test_http_400_mensagens():
    st, b = chamar(cep_origem="123", cep_destino="20040002", peso_kg="abc")
    assert st == 400 and len(b["detalhes"]) == 2
    st, b = chamar(cep_origem="01310100", cep_destino="20040002", peso_kg="50")
    assert st == 400 and "entre 0 e 30" in b["detalhes"][0]


def test_rotas():
    assert chamar("/health")[0] == 200
    assert chamar("/nao-existe")[0] == 404


if __name__ == "__main__":
    for nome, f in list(globals().items()):
        if nome.startswith("test_"):
            f()
            print("ok", nome)
