#!/usr/bin/env python3
"""att_probe.py — medição dos arquivos `.att` (atributo de terreno) da referência (fase R-5).

Somente leitura. O que este probe afirma é aritmética e contagem; a leitura de que os 65 536 bytes
restantes sejam uma grade 256x256 é HIPOTESE (testável: o tamanho bate exatamente e o prefixo é
constante), e sai marcada como hipótese no relatório, nunca como fato.

Saída: TSV por arquivo + bloco de agregados. Determinístico (sem timestamp de execução).
"""
import argparse
import collections
import hashlib
import os
import sys

ESPERADO = 65539          # medido em todos os 276 arquivos na primeira passada
CORPO = 65536             # 65539 - 3 == 256 * 256 (a hipótese da grade)
MARCADOR = bytes([0xFF, 0xFF])   # bytes 1-2: constantes nos 276 arquivos (medido)
# byte0 NAO e constante: mediu-se {0x00, 0x20}. Tratar como constante seria inventar estrutura.


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ext", default=".att")
    ap.add_argument("--amostra", type=int, default=0, help="0 = todos")
    a = ap.parse_args()
    root = os.environ.get("MU_REF_DATA", "").strip()
    if not root or not os.path.isdir(root):
        print("att_probe: MU_REF_DATA nao definido ou nao e um diretorio", file=sys.stderr)
        return 2
    ext = a.ext.lower()
    files = sorted(os.path.join(dp, fn)
                   for dp, _, fns in os.walk(root) for fn in fns if fn.lower().endswith(ext))
    print("arquivo\ttamanho\tsha256_16\tprefixo_8\ttamanho_esperado\tmarcador_ff_ff\t"
          "byte0\tbyte3\tvalores_distintos_no_corpo\tvalor_mais_comum\tpct_mais_comum")
    sizes = collections.Counter()
    prefixos = collections.Counter()
    byte0 = collections.Counter()
    byte3 = collections.Counter()
    globais = collections.Counter()
    n_ok = 0
    for i, p in enumerate(files):
        if a.amostra and i >= a.amostra:
            break
        rel = os.path.relpath(p, root)
        with open(p, "rb") as f:
            d = f.read()
        sizes[len(d)] += 1
        prefixos[d[1:3]] += 1
        byte0[d[0]] += 1
        if len(d) >= 4:
            byte3[d[3]] += 1
        corpo = d[3:] if len(d) > 3 else b""
        hist = collections.Counter(corpo)
        globais.update(hist)
        mc, mcn = (hist.most_common(1)[0] if hist else (0, 0))
        ok = len(d) == ESPERADO and d[1:3] == MARCADOR
        n_ok += ok
        print(f"{rel}\t{len(d)}\t{hashlib.sha256(d).hexdigest()[:16]}\t{d[:8].hex()}\t"
              f"{int(len(d) == ESPERADO)}\t{int(d[1:3] == MARCADOR)}\t{d[0]}\t"
              f"{d[3] if len(d) > 3 else -1}\t{len(hist)}\t{mc}\t"
              f"{round(100.0 * mcn / len(corpo), 2) if corpo else 0}")
    print("\n# agregados")
    print(f"# arquivos={sum(sizes.values())} tamanhos_distintos={len(sizes)} "
          f"tamanhos={dict(sizes)}")
    print(f"# bytes1_2_distintos={len(prefixos)} valores={[p.hex() for p in prefixos]} "
          f"(constante={'sim' if len(prefixos) == 1 else 'nao'})")
    print(f"# byte0_distintos={len(byte0)} valores={sorted(byte0)} -> byte0 NAO e constante")
    print(f"# byte3_distintos={len(byte3)} valores={sorted(byte3)}")
    print(f"# corpo={CORPO} bytes; {CORPO}==256*256 -> {CORPO == 256 * 256} "
          f"(HIPOTESE de grade 256x256, nao confirmada por especificacao)")
    print(f"# valores_distintos_no_conjunto={len(globais)} "
          f"top5={globais.most_common(5)}")
    print(f"# conformes_tamanho_e_marcador={n_ok}/{sum(sizes.values())}")
    return 0 if n_ok == sum(sizes.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
