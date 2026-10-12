#!/usr/bin/env python3
"""matrix_check.py — validador estrutural da matriz de evidências (fase R-6).

Uma matriz de evidências só vale se cada linha puder ser reproduzida. Este validador existe para
impedir que a matriz vire lista de intenções: linha sem comando reproduzível, sem resultado
observado ou sem conclusão permitida é erro, e o portão falha.

Uso: matrix_check.py <arquivo.tsv> [--coluna-teste "teste reproduzível"]
Exit: 0 válido · 1 inválido · 2 erro de uso.
"""
import argparse
import os
import sys

COLUNAS = ["hipotese", "fonte", "metodo", "resultado", "limitacoes", "confianca",
           "teste", "conclusao", "proxima"]
# o que cada coluna exige: não vazio e, para algumas, conteúdo mínimo
MINIMO = {"hipotese": 10, "fonte": 3, "metodo": 8, "resultado": 3, "confianca": 3,
          "teste": 6, "conclusao": 5}
CONFIANCAS = {"alta", "media", "baixa", "nenhuma"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("arquivo")
    a = ap.parse_args()
    if not os.path.isfile(a.arquivo):
        print(f"matrix_check: arquivo nao encontrado: {a.arquivo}", file=sys.stderr)
        return 2

    with open(a.arquivo, encoding="utf-8") as f:
        linhas = [l.rstrip("\n") for l in f if l.strip() and not l.startswith("#")]
    if not linhas:
        print("matrix_check: matriz vazia", file=sys.stderr)
        return 1

    cab = [c.strip().lower() for c in linhas[0].split("\t")]
    faltam = [c for c in COLUNAS if c not in cab]
    if faltam:
        print(f"matrix_check: colunas ausentes no cabecalho: {faltam}", file=sys.stderr)
        return 1
    idx = {c: cab.index(c) for c in COLUNAS}

    erros = []
    for i, l in enumerate(linhas[1:], start=2):
        cel = l.split("\t")
        if len(cel) != len(cab):
            erros.append(f"linha {i}: {len(cel)} celulas, cabecalho tem {len(cab)}")
            continue
        for col, minimo in MINIMO.items():
            v = cel[idx[col]].strip()
            if len(v) < minimo:
                erros.append(f"linha {i}: coluna '{col}' curta ou vazia ({len(v)}<{minimo})")
        conf = cel[idx["confianca"]].strip().lower()
        if conf not in CONFIANCAS:
            erros.append(f"linha {i}: confianca '{conf}' fora de {sorted(CONFIANCAS)}")
        teste = cel[idx["teste"]].strip()
        # comando reproduzível tem de citar um arquivo ou alvo que existe
        if not any(tok in teste for tok in ("make ", "bash ", "python3 ", "tools/", "tests/")):
            erros.append(f"linha {i}: teste reproduzivel nao cita comando/arquivo: '{teste}'")

    total = len(linhas) - 1
    if erros:
        for e in erros:
            print(f"matrix_check: {e}", file=sys.stderr)
        print(f"matrix_check: {len(erros)} problemas em {total} linhas", file=sys.stderr)
        return 1
    print(f"matrix_check: {total} linhas validas em {a.arquivo}")
    print(f"matrix_check: colunas={cab}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
