#!/usr/bin/env python3
"""
Recupera scripts Lua que so existem como lixo temporario do GameServer.

Contexto do achado (ver workspace/reports/):
  MuServer/GameServer*/t*.tmp  sao 504 arquivos de ~11,5 KB. 141 deles sao
  byte-identicos. O conteudo e um script Lua de balanceamento de dano PvP
  (hook em OnUserDamage) que NAO EXISTE em nenhum outro lugar do repositorio:
  grep por ALLOWED_CUSTOMER so casa em .tmp e .dmp. Ou seja, a UNICA copia
  legivel desse codigo eram os restos de uma sessao do LuaEncryptorTool.
  14 arquivos (2.198 bytes) sao a versao CRIPTOGRAFADA correspondente.

Este utilitario:
  - agrupa por hash, identifica cada conteudo unico, detecta variantes
  - grava cada conteudo unico recuperado em workspace/recovered/lua/
  - NAO apaga nada no MuServer/ (preservacao do estado original)
  - emite um relatorio JSON/TSV para o inventario

Uso: python3 workspace/tools/recover_tmp_lua.py [--root MuServer] [--out workspace/recovered/lua]
"""
import os
import re
import sys
import glob
import json
import hashlib
import argparse
import collections


def classify(data):
    """Retorna ('lua'|'binario-cifrado'|'vazio', titulo, n_linhas)."""
    if not data:
        return "vazio", "", 0
    head = data[:64]
    printable = sum(1 for c in head if 32 <= c < 127 or c in (9, 10, 13))
    if printable < 40:
        return "binario-cifrado", "", 0
    txt = data.decode("utf-8", "replace")
    lines = [l for l in txt.splitlines() if l.strip()]
    title = ""
    for i, l in enumerate(lines):
        m = re.match(r"\s*--\s*(?:PvP|BALANCE|Balance|[A-Za-z][A-Za-z0-9 ()+/&,.:_-]{3,70})\s*$", l)
        if m:
            title = l.strip().lstrip("-").strip()
            break
    if not title:
        for l in lines[:12]:
            m = re.match(r"\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{", l)
            if m:
                title = "tabela " + m.group(1)
                break
    return "lua", title, len(lines)


def looks_complete(data):
    """Heuristica de completude: termina em attach/return/end e parenteses batem."""
    if not data:
        return False
    t = data.decode("utf-8", "replace")
    t = re.sub(r"--\[\[.*?\]\]", "", t, flags=re.S)
    t = re.sub(r"--[^\n]*", "", t)
    depth = 0
    for kw in re.finditer(r"\b(function|if|for|while|do|end|repeat|until)\b", t):
        w = kw.group(1)
        if w in ("function", "if", "for", "while", "do"):
            depth += 1
        elif w == "end":
            depth -= 1
    tail = [l.strip() for l in t.splitlines() if l.strip()][-1:] or [""]
    return depth == 0 and (tail[0].endswith("end") or "BridgeFunctionAttach" in tail[0]
                           or tail[0].startswith("return"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/home/user/Muserver/MuServer")
    ap.add_argument("--out", default="/home/user/Muserver/workspace/recovered/lua")
    a = ap.parse_args()

    files = sorted(glob.glob(os.path.join(a.root, "**", "*.tmp"), recursive=True))
    if not files:
        print("nenhum .tmp encontrado em", a.root)
        return 1
    groups = collections.defaultdict(list)
    for f in files:
        data = open(f, "rb").read()
        groups[hashlib.sha256(data).hexdigest()].append(f)

    os.makedirs(a.out, exist_ok=True)
    recs = []
    for i, (h, fl) in enumerate(sorted(groups.items(), key=lambda kv: -len(kv[1])), 1):
        data = open(fl[0], "rb").read()
        kind, title, nl = classify(data)
        complete = looks_complete(data) if kind == "lua" else False
        slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")[:40] or "sem_nome"
        name = "rec%02d_%s_%s_%s.lua" % (i, kind.split("-")[0], slug, h[:10])
        if kind == "lua":
            dst = os.path.join(a.out, name)
            open(dst, "wb").write(data)
        elif kind == "binario-cifrado":
            dst = os.path.join(a.out, name.replace(".lua", ".enc"))
            open(dst, "wb").write(data)
        else:
            dst = None
        recs.append({
            "sha256": h, "copies": len(fl), "bytes": len(data),
            "kind": kind, "title": title, "lines": nl,
            "syntactically_complete": complete,
            "written_to": dst,
            "sample_paths": fl[:3],
            "all_paths": fl,
        })

    # mapa arquivo -> grupo, para o relatorio de pod
    by_hash = {r["sha256"]: r for r in recs}
    print("=" * 92)
    print("RECUPERACAO DE SCRIPTS LUA PERDIDOS EM LIXO TEMPORARIO")
    print("=" * 92)
    print("arquivos .tmp examinados : %d" % len(files))
    print("conteudos unicos         : %d" % len(recs))
    print("  lua legivel            : %d" % sum(1 for r in recs if r["kind"] == "lua"))
    print("  binario cifrado (OZ)   : %d" % sum(1 for r in recs if r["kind"] == "binario-cifrado"))
    print("  vazio                  : %d" % sum(1 for r in recs if r["kind"] == "vazio"))
    red = len(files) - len(recs)
    print("bytes ocupados pelos .tmp: %s" % "{:,}".format(sum(r["bytes"] * r["copies"] for r in recs)))
    print("reduzivel a (dedupe)     : %s  (%.1f%% de redundancia)" % (
        "{:,}".format(sum(r["bytes"] for r in recs)), 100.0 * red / max(1, len(files))))
    print()
    print("%-4s %-18s %6s %8s %-6s %s" % ("#", "TIPO", "COPIAS", "BYTES", "OK?", "TITULO"))
    for r in sorted(recs, key=lambda x: -x["copies"])[:14]:
        print("%-4d %-18s %6d %8d %-6s %s" % (
            recs.index(r) + 1, r["kind"], r["copies"], r["bytes"],
            "sim" if r["syntactically_complete"] else "NAO", r["title"][:52]))
    js = os.path.join(a.out, "_recovery_report.json")
    json.dump({"total_tmp": len(files), "unique": len(recs), "records": recs},
              open(js, "w"), indent=1, ensure_ascii=False)
    tsv = os.path.join(a.out, "_recovery_report.tsv")
    with open(tsv, "w") as f:
        f.write("sha256\tcopies\tbytes\tkind\tcomplete\ttitle\tsample\n")
        for r in recs:
            f.write("%s\t%d\t%d\t%s\t%s\t%s\t%s\n" % (r["sha256"], r["copies"], r["bytes"],
                     r["kind"], r["syntactically_complete"], r["title"].replace("\t", " "),
                     r["sample_paths"][0]))
    print()
    print("relatorios: %s\n          %s" % (js, tsv))
    print("nenhum arquivo original foi alterado ou removido.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
