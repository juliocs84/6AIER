# Nota sobre a primeira rodada de medições (17/11/2026, 22:24)

A primeira execução do `evidencias.sh` mediu a Lambda ainda com o código `v1-mock`, que o
Terraform publica no apply; o `qc publica v2` não tinha sido aplicado. Os sinais foram estes:
`preco_max=abc` e `preco_max=0` devolveram 200, a duração ficou em ~2 ms e o uso de memória em 32 MB,
compatível com uma função sem acesso ao S3.

Por isso, as medições de cold start (1.3), CloudWatch (2.3) e benchmark (3.2) foram **refeitas**
às 22:43 com a `v2-s3` publicada e verificada (`/health` → "source": "s3"; `preco_max=abc` → 400).
Ver `publicacao-v2-e-container.txt`. Só as medições refeitas aparecem no documento.

Da primeira rodada, aproveitamos apenas as evidências que não dependem do código do catálogo:
- o drift (3.3);
- o segredo, o agendamento e o auto scaling (3.4);
- as chamadas à tool de frete (2.2).

Também ficou registrada uma observação: depois de só 6 minutos ociosa, a chamada já veio fria
(`Init Duration: 87,38 ms`).
