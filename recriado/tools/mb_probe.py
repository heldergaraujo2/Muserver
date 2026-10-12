#!/usr/bin/env python3
"""mb_probe.py — medição de modelos e texturas nativos (.bmd/.smd/.ozt/.ozj) da referência (R-5).

Somente leitura. Regra da fase: **não inventar assinatura**. Este probe classifica pelo que está no
arquivo (magic bytes verificáveis) e, onde há padrão suspeito, formula hipótese e a testa por medida
— nunca apresenta hipótese como estrutura confirmada.

Casos medidos na primeira passada e o que se faz com cada um:
  .ozj  começa com FFD8 e termina com FFD9  -> JPEG; verificável arquivo a arquivo.
  .smd  começa com "version 1\\n"            -> texto; contável em linhas/seções.
  .ozt  prefixo de 8 bytes repetido          -> medido, sem decodificação afirmada.
  .bmd  região inicial com padrão de 3 bytes -> HIPOTESE de XOR com chave de 3 bytes; o probe
        mede a razão de bytes imprimíveis antes/depois de aplicar a chave candidata. Se a razão não
        subir, a hipótese é descartada no relatório.
"""
import argparse
import collections
import hashlib
import os
import sys


def printable_ratio(b: bytes) -> float:
    if not b:
        return 0.0
    ok = sum(1 for x in b if 32 <= x < 127 or x in (9, 10, 13))
    return round(100.0 * ok / len(b), 2)


def classe(path: str, d: bytes):
    low = path.lower()
    if d[:2] == b"\xff\xd8" and d[-2:] == b"\xff\xd9":
        return "jpeg_completo"
    if d[:2] == b"\xff\xd8":
        return "jpeg_sem_eoi"
    if d.startswith(b"version 1\n"):
        return "texto_smd"
    if low.endswith(".ozt"):
        return "ozt_prefixo_" + d[:8].hex()
    return "binario_nao_classificado"


def chave_xor3(d: bytes, janela: int = 8192):
    """Candidato a chave de 3 bytes: o triplo mais frequente em cada posição módulo 3."""
    amostra = d[:janela]
    if len(amostra) < 64:
        return None
    cols = [collections.Counter() for _ in range(3)]
    for i, x in enumerate(amostra):
        cols[i % 3][x] += 1
    chave = bytes(c.most_common(1)[0][0] for c in cols)
    if chave == b"\x00\x00\x00":
        return None
    return chave


def aplicar_xor(d: bytes, chave: bytes, limite: int = 65536) -> bytes:
    n = min(len(d), limite)
    return bytes(d[i] ^ chave[i % 3] for i in range(n))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ext", default=".bmd,.smd,.ozt,.ozj")
    ap.add_argument("--amostra", type=int, default=0)
    a = ap.parse_args()
    root = os.environ.get("MU_REF_DATA", "").strip()
    if not root or not os.path.isdir(root):
        print("mb_probe: MU_REF_DATA nao definido ou nao e um diretorio", file=sys.stderr)
        return 2
    exts = tuple(e.strip().lower() for e in a.ext.split(",") if e.strip())
    files = sorted(os.path.join(dp, fn)
                   for dp, _, fns in os.walk(root) for fn in fns if fn.lower().endswith(exts))
    print("arquivo\text\ttamanho\tsha256_16\tclasse\timprimivel_pct\txor3_chave\t"
          "imprimivel_pos_xor_pct\tlinhas\tdelta_imprimivel")
    por_classe = collections.Counter()
    por_ext = collections.Counter()
    deltas = []
    for i, p in enumerate(files):
        if a.amostra and i >= a.amostra:
            break
        rel = os.path.relpath(p, root)
        ext = os.path.splitext(p)[1].lower()
        with open(p, "rb") as f:
            d = f.read()
        c = classe(p, d)
        por_classe[c.split("_prefixo")[0]] += 1
        por_ext[ext] += 1
        antes = printable_ratio(d[:65536])
        chave = chave_xor3(d) if ext == ".bmd" else None
        depois = ""
        delta = ""
        if chave:
            depois = printable_ratio(aplicar_xor(d, chave))
            delta = round(depois - antes, 2)
            deltas.append(delta)
        linhas = d.count(b"\n") if c == "texto_smd" else ""
        print(f"{rel}\t{ext}\t{len(d)}\t{hashlib.sha256(d).hexdigest()[:16]}\t{c}\t{antes}\t"
              f"{chave.hex() if chave else ''}\t{depois}\t{linhas}\t{delta}")
    print("\n# agregados")
    print(f"# por_extensao={dict(por_ext)}")
    print(f"# por_classe={dict(por_classe)}")
    if deltas:
        print(f"# hipotese XOR3 em .bmd: delta_imprimivel min={min(deltas)} mediana="
              f"{sorted(deltas)[len(deltas) // 2]} max={max(deltas)} "
              f"(delta>0 sustenta a hipotese; delta~0 a descarta)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
