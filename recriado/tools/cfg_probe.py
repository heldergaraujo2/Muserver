#!/usr/bin/env python3
"""cfg_probe.py — inventário reproduzível dos `.ini` da referência (fase R-6).

Somente leitura. Mede onde vivem portas, endereços e parâmetros — a R-5 mostrou que as portas
não estão em string nos binários, então a configuração é a evidência disponível.

SEGREDOS: o pacote original traz credenciais em claro (senha global, token de bot, hardware id).
Esta sonda **nunca** imprime valor de chave sensível: substitui por
`<REDACTED bytes=N forma=...>`. A redação é verificada por `tests/cfg.sh`, não prometida aqui.
Regra do projeto: nenhum segredo entra em arquivo versionado.

Saída: TSV determinístico, caminhos relativos, sem timestamp.
"""
import argparse
import collections
import os
import re
import sys

# chave cujo valor é tratado como segredo (comparação em minúsculas, por substring)
CHAVE_SENSIVEL = ("pass", "senha", "pwd", "token", "secret", "credential", "key",
                  "hardwareid", "hwid", "license", "licenca", "auth", "signature",
                  # 2026-10-14 (P07-x): "serial" entrou porque `ClientSerial` (serial de cliente,
                  # 16 chars) NAO casava nenhuma das entradas acima nem as formas RE_TOKEN/RE_GUID,
                  # e por isso saiu em claro no `reports/r6-config.tsv` versionado. Achado pela
                  # varredura anti-vazamento (`workspace/tests/run_all.sh`) rodando o scanner
                  # `workspace/tools/verifica_doc_sem_segredo.py` sobre os arquivos proprios.
                  "serial")
# forma de valor que denuncia segredo mesmo com nome de chave inocente
RE_TOKEN = re.compile(r"^[A-Za-z0-9_\-]{32,}(\.[A-Za-z0-9_\-]+)+$")
RE_GUID = re.compile(r"^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$")
RE_IP = re.compile(r"^(\d{1,3}\.){3}\d{1,3}$")


def sensivel(chave: str, valor: str) -> bool:
    k = chave.lower()
    if any(s in k for s in CHAVE_SENSIVEL):
        return True
    if RE_TOKEN.match(valor) or RE_GUID.match(valor):
        return True
    return False


def redact(valor: str) -> str:
    forma = []
    if any(c.isdigit() for c in valor):
        forma.append("dig")
    if any(c.isalpha() for c in valor):
        forma.append("alfa")
    if any(c in ".-_@" for c in valor):
        forma.append("punct")
    return "<REDACTED bytes=%d forma=%s>" % (len(valor.encode("utf-8", "replace")),
                                             "+".join(forma) or "vazio")


def classe(chave: str, valor: str) -> str:
    if RE_IP.match(valor):
        return "ipv4"
    if re.fullmatch(r"\d+", valor):
        # "porta" so quando a CHAVE diz que e porta: classificar todo inteiro 1..65535 como porta
        # fazia MaxIpConnection=20 e Owner=1 aparecerem na lista de endpoints.
        if 1 <= int(valor) <= 65535 and "port" in chave.lower():
            return "porta"
        return "bool" if valor in ("0", "1") else "inteiro"
    if valor == "":
        return "vazio"
    return "texto"


def parse(caminho: str):
    with open(caminho, "rb") as f:
        bruto = f.read()
    # os .ini do pacote não são UTF-8 limpo (há bytes isolados de acentuação)
    texto = bruto.decode("latin-1", "replace")
    secao = ""
    pares = []
    for linha in texto.splitlines():
        l = linha.strip()
        if not l or l.startswith(("//", ";", "#")):
            continue
        if l.startswith("[") and l.endswith("]"):
            secao = l[1:-1].strip()
            continue
        if "=" not in l:
            continue
        k, _, v = l.partition("=")
        pares.append((secao, k.strip(), v.strip()))
    return pares


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ext", default=".ini")
    ap.add_argument("--so-portas", action="store_true")
    ap.add_argument("--so-sensiveis", action="store_true",
                    help="lista apenas as chaves redigidas (auditoria de segredos)")
    a = ap.parse_args()
    root = os.environ.get("MU_REF_DATA", "").strip()
    if not root or not os.path.isdir(root):
        print("cfg_probe: MU_REF_DATA nao definido ou nao e um diretorio", file=sys.stderr)
        return 2
    exts = tuple(e.strip().lower() for e in a.ext.split(",") if e.strip())
    files = sorted(os.path.join(dp, fn) for dp, _, fns in os.walk(root)
                   for fn in fns if fn.lower().endswith(exts))

    print("arquivo\tsecao\tchave\tclasse\tvalor")
    n_par = n_red = 0
    portas = collections.Counter()
    ips = collections.Counter()
    secoes = collections.Counter()
    for p in files:
        rel = os.path.relpath(p, root)
        try:
            pares = parse(p)
        except OSError:
            print(f"{rel}\t-\t-\tERRO_LEITURA\t-")
            continue
        for sec, k, v in pares:
            n_par += 1
            secoes[sec] += 1
            seg = sensivel(k, v)
            cl = "segredo" if seg else classe(k, v)
            shown = redact(v) if seg else v
            if cl == "porta":
                portas[int(v)] += 1
            if cl == "ipv4":
                ips[v] += 1
            if seg:
                n_red += 1
            if a.so_portas and cl not in ("porta", "ipv4"):
                continue
            if a.so_sensiveis and not seg:
                continue
            print(f"{rel}\t{sec}\t{k}\t{cl}\t{shown}")

    print("\n# agregados")
    print(f"# arquivos={len(files)} pares_chave_valor={n_par} segredos_redigidos={n_red}")
    print(f"# portas={dict(sorted(portas.items()))}")
    print(f"# ipv4={dict(sorted(ips.items()))}")
    print(f"# secoes={dict(sorted(secoes.items()))}")
    print("# nenhum valor sensivel foi impresso; a redacao e verificada por tests/cfg.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
