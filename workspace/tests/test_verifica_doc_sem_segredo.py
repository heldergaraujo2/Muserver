#!/usr/bin/env python3
"""Teste da ferramenta anti-vazamento (`workspace/tools/verifica_doc_sem_segredo.py`).

Dois testes importam aqui, e os dois sao igualmente obrigatorios:
  1. a ferramenta DETECTA segredo plantado (senao e decoracao);
  2. a ferramenta NAO VAZA o valor na propria saida (senao e o problema, nao a solucao).

Todos os valores usados aqui sao SINTETICOS. Nenhum valor real do pacote e lido, impresso ou
comparado — o caso final roda a ferramenta contra os documentos reais e exige 0 casamentos.

Contrato de saida: `# verifica_segredo=<n> falhas=<f>`
"""
from __future__ import annotations

import io
import os
import re
import subprocess
import sys
import tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FERR = os.path.join(RAIZ, "workspace", "tools", "verifica_doc_sem_segredo.py")

n = 0
falhas = 0


def ck(desc: str, cond: bool) -> None:
    global n, falhas
    n += 1
    if cond:
        print(f"ok {n} - {desc}")
    else:
        falhas += 1
        print(f"not ok {n} - {desc}")


def roda(args: list[str], entrada: str = "") -> tuple[int, str]:
    p = subprocess.run([sys.executable, FERR] + args, capture_output=True, text=True, input=entrada)
    return p.returncode, p.stdout + p.stderr


# Valor sintetico, com forma de credencial, que NUNCA existe no pacote.
SEGREDO = "Zq7-Planted-Synthetic-Secret-1234567890"
SENHA_CURTA = "1234"

tmp = tempfile.mkdtemp(prefix="verifica-segredo.")
fonte = os.path.join(tmp, "config.ini")
with open(fonte, "w", encoding="utf-8") as fh:
    fh.write("[Database]\n")
    fh.write(f"sqlsenha={SEGREDO}\n")
    fh.write(f"pwd={SENHA_CURTA}\n")
    fh.write("sqldatabase=MuOnline\n")
    fh.write("senha_vazia=\n")
    fh.write("senha_placeholder=changeme\n")

limpo = os.path.join(tmp, "limpo.md")
with open(limpo, "w", encoding="utf-8") as fh:
    fh.write("# Relatorio\n\nA senha do banco foi redigida por politica de seguranca.\n")

sujo = os.path.join(tmp, "sujo.md")
with open(sujo, "w", encoding="utf-8") as fh:
    fh.write(f"# Relatorio\n\nsqlsenha={SEGREDO}\n")

# alvo que so carrega o valor CURTO: e ele que testa o limite de --min-len (usar o `sujo` ali seria
# medir outra coisa — o teste estaria errado, nao a ferramenta)
curto = os.path.join(tmp, "curto.md")
with open(curto, "w", encoding="utf-8") as fh:
    # chave com o token sensivel colado no separador: e a forma que o extrator reconhece
    fh.write(f"# Relatorio\n\npwd={SENHA_CURTA}\n")

# ---------------------------------------------------------------- 1) o caso limpo passa
rc, saida = roda(["--alvo", limpo, "--fontes", fonte, "--raiz", tmp])
ck("documento sem valor sensivel sai 0", rc == 0)
ck("resumo diz 0 casamentos", "por_valor=0" in saida and "por_forma=0" in saida)
ck("a saida informa quantas fontes foram lidas", "fontes: 1/1 presentes" in saida)

# ---------------------------------------------------------------- 2) o caso sujo e DETECTADO
rc, saida = roda(["--alvo", sujo, "--fontes", fonte, "--raiz", tmp, "--detalhar"])
ck("documento com o valor sensivel plantado sai 1", rc == 1)
ck("o nome da CHAVE aparece no achado (util para corrigir)", "sqlsenha" in saida)
ck("a contagem de casamentos e reportada", "por_valor=1" in saida)

# ---------------------------------------------------------------- 3) a ferramenta NAO vaza o valor
ck("*** a saida NAO contem o valor plantado (nem na linha de detalhe) ***", SEGREDO not in saida)
ck("a saida tambem nao traz o valor em pedacos longos",
   not any(t in saida for t in [SEGREDO[:20], SEGREDO[-20:]]))
rc_json, _ = roda(["--alvo", sujo, "--fontes", fonte, "--raiz", tmp, "--json", tmp + "/r.json"])
bruto_json = open(tmp + "/r.json", encoding="utf-8").read()
ck("o JSON de resultado tambem nao contem o valor", SEGREDO not in bruto_json)
ck("mesmo em falha o codigo e 1 (nao 2/3: falha de execucao e outra coisa)", rc_json == 1)

# ---------------------------------------------------------------- 4) limites declarados
rc, saida = roda(["--alvo", curto, "--fontes", fonte, "--raiz", tmp])
ck("valor curto (4 digitos) e ignorado por padrao -- limite declarado, nao surpresa",
   rc == 0 and "por_valor=0" in saida)
rc, saida = roda(["--alvo", curto, "--fontes", fonte, "--raiz", tmp, "--min-len", "3"])
ck("com --min-len menor o mesmo valor curto aparece (o limite e configuravel)",
   rc == 1 and "por_valor=1" in saida)

# ---------------------------------------------------------------- 5) erro de uso nao vira "aprovado"
rc, saida = roda(["--alvo", os.path.join(tmp, "nao-existe.md"), "--fontes", fonte, "--raiz", tmp])
ck("alvo ausente sai 2 (erro de execucao != documento limpo)", rc == 2)
rc, saida = roda(["--fontes", fonte, "--raiz", tmp])
ck("sem --alvo a ferramenta recusa (nao 'aprova por omissao')", rc == 2)
rc, saida = roda(["--alvo", limpo, "--fontes", os.path.join(tmp, "nao-existe.ini"), "--raiz", tmp])
ck("fonte ausente e declarada e o alvo limpo continua passando", rc == 0 and "fontes: 0/1" in saida)

# ---------------------------------------------------------------- 5b) a checagem por FORMA
# Cobre o ponto cego da checagem por valor: linha de credencial cujo valor curto nao esta na fonte.
forma = os.path.join(tmp, "forma.md")
with open(forma, "w", encoding="utf-8") as fh:
    fh.write("# Relatorio\n\nglobalpassword=Ab3xK9Lm2Qr7\n")
redigido = os.path.join(tmp, "redigido.md")
with open(redigido, "w", encoding="utf-8") as fh:
    fh.write("# Relatorio\n\nglobalpassword=<redigido>\nsqlsenha: REDIGIDO\n"
             "pwd=COLE_AQUI_VIA_VARIAVEL_DE_AMBIENTE\n")
rc, saida = roda(["--alvo", forma, "--fontes", fonte, "--raiz", tmp])
ck("linha de credencial colada no documento e detectada por FORMA", rc == 1 and "por_forma=1" in saida)
ck("o achado por forma nomeia a chave e nao o valor", "globalpassword" in saida and "Ab3xK9Lm2Qr7" not in saida)
rc, saida = roda(["--alvo", redigido, "--fontes", fonte, "--raiz", tmp])
ck("marcadores de redacao (<redigido>, REDIGIDO, COLE_AQUI_...) nao sao vazamento", rc == 0)

# ---------------------------------------------------------------- 6) caso real: os documentos nossos
docs = [
    "workspace/seguranca/INVENTARIO-EXPOSICAO-2026-10-13.md",
    "workspace/seguranca/AVALIACAO-RISCO-E-PLANO-ROTACAO-2026-10-13.md",
    "workspace/reports/A1-secrets.md",
]
existentes = [d for d in docs if os.path.isfile(os.path.join(RAIZ, d))]
ck("os documentos de seguranca existem para serem verificados", len(existentes) >= 2)
if existentes:
    rc, saida = roda([a for d in existentes for a in ("--alvo", os.path.join(RAIZ, d))])
    ck("os documentos de seguranca reais nao carregam valor sensivel do pacote (0 casamentos)",
       rc == 0 and "total=0" in saida)
    # o autor do documento pode conferir de onde vem o numero, sem ver valor nenhum
    ck("a verificacao mostra quantos valores foram extraidos das fontes reais",
       re.search(r"valores_extraidos=(\d+)", saida) is not None
       and int(re.search(r"valores_extraidos=(\d+)", saida).group(1)) > 0)

print(f"1..{n}")
print(f"# verifica_segredo={n} falhas={falhas}")
sys.exit(1 if falhas else 0)
