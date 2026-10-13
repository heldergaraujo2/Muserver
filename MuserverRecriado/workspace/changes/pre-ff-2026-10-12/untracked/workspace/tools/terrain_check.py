#!/usr/bin/env python3
"""
Valida as posicoes de spawn contra o TERRENO REAL (.att) e calibra a regra de
walkabilidade a partir do que o proprio GameServer registrou nos logs.

Formato do .att (confirmado por inspecao binaria):
  byte0 = 0 (marcador)   byte1 = largura-1   byte2 = altura-1
  em seguida (largura*altura) bytes de atributo, em linha-major.
  Terreno de 256x256 -> 3 + 65536 = 65539 bytes (tamanho observado).

Metodo de calibracao (empirico, nao suposicao):
  1. extrai dos logs as linhas `[MonsterSetBase] Incorrect Monster Position:
     (Monster: N, Map: M, X: x, Y: y)` -> o conj. REJEITADO pelo servidor
  2. le o atributo do terreno nesses (M,x,y)
  3. compara com a distribuicao global dos atributos do mesmo mapa
  4. se os rejeitados se concentram em poucos valores de atributo, temos a regra

Uso: python3 workspace/tools/terrain_check.py [--root MuServer]
"""
import os
import re
import sys
import glob
import json
import argparse
import collections

LOG_LINE = re.compile(
    r"Incorrect Monster Position:\s*\(Monster:\s*(\d+),\s*Map:\s*(\d+),\s*X:\s*(\d+),\s*Y:\s*(\d+)\)")


def terrain_dir(root):
    for cand in ("Data/Terrain", "Data/terrain", "DATA/Terrain"):
        p = os.path.join(root, cand)
        if os.path.isdir(p):
            return p
    d = glob.glob(os.path.join(root, "**", "Terrain"), recursive=True)
    d = [x for x in d if os.path.isdir(x)]
    return d[0] if d else None


def load_terrain(path):
    b = open(path, "rb").read()
    if len(b) < 4:
        return None
    w, h = b[1] + 1, b[2] + 1
    need = 3 + w * h
    if len(b) < need:
        h = (len(b) - 3) // w if w else 0
    return {"w": w, "h": h, "grid": b, "path": path}


def attr_at(t, x, y):
    if t is None:
        return None
    if not (0 <= x < t["w"] and 0 <= y < t["h"]):
        return "FORA"
    return t["grid"][3 + y * t["w"] + x]


def find_terrain(tdir, mp):
    for name in ("Terrain%d.att" % mp, "Terrain%d.Att" % mp):
        p = os.path.join(tdir, name)
        if os.path.exists(p):
            return p
    hits = [p for p in glob.glob(os.path.join(tdir, "*.att"))
            if re.match(r"^terrain%d\." % mp, os.path.basename(p), re.I)]
    return hits[0] if hits else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/home/user/Muserver/MuServer")
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    tdir = terrain_dir(root)
    if not tdir:
        print("diretorio Terrain nao encontrado")
        return 2

    have = {}
    for p in glob.glob(os.path.join(tdir, "*.att")):
        m = re.match(r"[Tt]errain(\d+)\.[Aa][Tt][Tt]$", os.path.basename(p))
        if m:
            have[int(m.group(1))] = p
    named = {os.path.basename(p): p for p in glob.glob(os.path.join(tdir, "*.att"))
             if not re.match(r"[Tt]errain\d+\.[Aa][Tt][Tt]$", os.path.basename(p))}

    print("=" * 92)
    print("VALIDACAO DE SPAWN vs TERRENO  |  %s" % tdir)
    print("=" * 92)
    print("arquivos .att: %d numerados + %d por nome (%s)" % (
        len(have), len(named), ", ".join(sorted(named)[:6])))
    print("mapas com terreno: %s" % sorted(have)[:40])

    # ---- mapas referenciados por dados, sem terreno ----
    used = set()
    for f in glob.glob(os.path.join(root, "Data", "MonsterSetBase", "**", "*.txt"), recursive=True):
        b = os.path.basename(f)
        m = re.match(r"^(\d+)\s*-\s", b)
        if m:
            used.add(int(m.group(1)))
        for line in open(f, encoding="utf-8", errors="replace"):
            parts = line.split()
            if len(parts) >= 6 and re.match(r"^\d+$", parts[0]) and re.match(r"^0?\d+$", parts[1]):
                try:
                    used.add(int(parts[1]))
                except ValueError:
                    pass
    missing = sorted(used - set(have))
    print()
    print("mapas referenciados em MonsterSetBase: %d" % len(used))
    if missing:
        print("[ERRO] %d mapa(s) com spawn(s) sem arquivo de terreno: %s" % (
            len(missing), ", ".join(map(str, missing))))
        print("       -> sem Terrain<map>.att o servidor nao tem atributo de tile:")
        print("          e exatamente o padrao dos erros 'Incorrect Monster Position' nos mapas citados")
    else:
        print("[OK] todo mapa referenciado tem terreno")

    # ---- coleta dos rejeitados pelo servidor ----
    rejected = collections.Counter()
    rejected_rows = []
    logs = glob.glob(os.path.join(root, "**", "LOG", "*.txt"), recursive=True)
    for lg in logs:
        try:
            txt = open(lg, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in LOG_LINE.finditer(txt):
            mon, mp, x, y = map(int, m.groups())
            rejected[(mp, attr_at(load_terrain(have[mp]) if mp in have else None, x, y))] += 1
            rejected_rows.append((mp, mon, x, y))
    print()
    print("linhas 'Incorrect Monster Position' nos logs: %d (em %d dias/arquivos)" % (
        sum(rejected.values()), len(logs)))

    # ---- calibracao ----
    cache = {}

    def terr(mp):
        if mp not in cache:
            p = have.get(mp)
            cache[mp] = load_terrain(p) if p else None
        return cache[mp]

    by_map = collections.defaultdict(collections.Counter)
    for (mp, at), n in rejected.items():
        by_map[mp][at] += n
    print()
    print("%-6s %-10s %-28s %s" % ("MAPA", "REJEITADOS", "ATRIBUTO DO TILE REJEITADO", "DISTRIBUICAO GLOBAL DO MAPA"))
    print("-" * 96)
    rules = collections.Counter()
    for mp, cnt in sorted(by_map.items(), key=lambda kv: -sum(kv[1].values()))[:10]:
        t = terr(mp)
        top = cnt.most_common(4)
        if t:
            g = collections.Counter(t["grid"][3:3 + t["w"] * t["h"]])
            gtot = sum(g.values())
            gstr = " ".join("%d:%.1f%%" % (k, 100.0 * v / gtot) for k, v in g.most_common(5))
        else:
            gstr = "(sem terreno)"
        print("%-6s %-10d %-28s %s" % (mp, sum(cnt.values()),
                                       ", ".join("%s=%dx" % (k, v) for k, v in top), gstr))
        for at, n in top:
            if isinstance(at, int):
                rules[at] += n
    if rules:
        dom = rules.most_common(5)
        tot = sum(rules.values())
        print()
        print("atributo(s) dominante(s) entre os rejeitados: %s" %
              ", ".join("%d = %d/%d (%.0f%%)" % (k, v, tot, 100.0 * v / tot) for k, v in dom))
        print("interpretacao candidata: tile cujo atributo contem esse valor e"
              " intransitavel para monstro -> o spawn deve ser movido ou o terreno corrigido")

    out = {"maps_used": sorted(used), "maps_with_terrain": sorted(have),
           "missing_terrain": missing, "rejected_total": sum(rejected.values()),
           "rejected_by_map_attr": {str(k): dict((str(a), n) for (m2, a), n in rejected.items() if m2 == k)
                                    for k, v in by_map.items()},
           "dominant_attrs": dict((str(k), v) for k, v in rules.items())}
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1)
        print("\njson: %s" % a.json)
    return 1 if (missing or rejected) else 0


if __name__ == "__main__":
    sys.exit(main())
