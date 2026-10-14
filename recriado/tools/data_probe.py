#!/usr/bin/env python3
"""data_probe.py — inventário reproduzível dos dados da referência (fase R-5).

Somente leitura. Mede o que existe; não restaura banco, não executa script, não abre .bak como
banco (só o cabeçalho, para dizer o que é). Saída determinística em blocos nomeados.

Blocos: inventario (contagem/tamanho por extensão e diretório), lua (tamanho de arquivos e linhas),
dados_texto (estrutura tabular dos .txt de dados), binarios_config (cabeçalho dos .dat),
db_backups (cabeçalho dos .bak), ferramentas_lua (arquivos com 'luaenc' no nome).
"""
import argparse
import collections
import hashlib
import os
import sys

MAX_AMOSTRA_TEXTO = 40


def bloco(nome: str) -> None:
    print(f"\n# === {nome} ===")


def inventario(root: str, alvo: str) -> None:
    bloco(f"inventario de {alvo}")
    print("diretorio\textensao\tarquivos\tbytes")
    agg = collections.defaultdict(lambda: [0, 0])
    for dp, _, fns in os.walk(os.path.join(root, alvo) if alvo else root):
        for fn in fns:
            p = os.path.join(dp, fn)
            ext = os.path.splitext(fn)[1].lower() or "(sem)"
            d = os.path.relpath(dp, root) or "."
            try:
                sz = os.path.getsize(p)
            except OSError:
                continue
            a = agg[(d, ext)]
            a[0] += 1
            a[1] += sz
    for (d, ext), (n, sz) in sorted(agg.items()):
        print(f"{d}\t{ext}\t{n}\t{sz}")


def lua_stats(root: str) -> None:
    bloco("lua")
    print("arquivo\tbytes\tlinhas\tmaior_linha\tcrlf\tnon_ascii")
    files = sorted(os.path.join(dp, fn) for dp, _, fns in os.walk(root)
                   for fn in fns if fn.lower().endswith(".lua"))
    tot = [0, 0, 0]
    maior = ("", 0)
    for p in files:
        with open(p, "rb") as f:
            d = f.read()
        linhas = d.count(b"\n")
        ml = max((len(x) for x in d.split(b"\n")), default=0)
        na = sum(1 for x in d if x > 127)
        crlf = 1 if b"\r\n" in d else 0   # fora do f-string: py3.11 nao aceita backslash nele
        tot[0] += len(d)
        tot[1] += linhas
        tot[2] += 1
        if len(d) > maior[1]:
            maior = (os.path.relpath(p, root), len(d))
        print(f"{os.path.relpath(p, root)}\t{len(d)}\t{linhas}\t{ml}\t{crlf}\t{na}")
    print(f"# total: arquivos={tot[2]} bytes={tot[0]} linhas={tot[1]} maior_arquivo={maior[0]} "
          f"({maior[1]} bytes)")


def dados_texto(root: str) -> None:
    bloco("dados_texto (estrutura tabular medida, sem interpretar colunas)")
    print("arquivo\tlinhas\tdelimitador\tcolunas_min\tcolunas_max\tbytes")
    base = os.path.join(root, "Data")
    if not os.path.isdir(base):
        print("# Data/ ausente")
        return
    feitos = 0
    for dp, _, fns in os.walk(base):
        for fn in sorted(fns):
            if not fn.lower().endswith(".txt") or feitos >= MAX_AMOSTRA_TEXTO:
                continue
            p = os.path.join(dp, fn)
            with open(p, "rb") as f:
                d = f.read(1 << 20)
            if not d or d[:2] in (b"\xff\xfe", b"\xfe\xff") or b"\x00" in d[:64]:
                continue  # não é texto simples: registrado como binário, não adivinhado
            delims = {"tab": d.count(b"\t"), ";": d.count(b";"), ",": d.count(b","),
                      "|": d.count(b"|")}
            nome, _ = max(delims.items(), key=lambda kv: kv[1])
            sep = {"tab": b"\t", ";": b";", ",": b",", "|": b"|"}[nome]
            ls = [x for x in d.split(b"\n") if x.strip()]
            cols = [x.count(sep) + 1 for x in ls] or [0]
            print(f"{os.path.relpath(p, root)}\t{len(ls)}\t{nome}\t{min(cols)}\t{max(cols)}\t{len(d)}")
            feitos += 1
    print(f"# amostrados={feitos} (limite {MAX_AMOSTRA_TEXTO}; o conjunto completo fica no bloco inventario)")


def binarios_config(root: str) -> None:
    bloco("binarios_config (cabeçalho medido, formato não decodificado)")
    print("arquivo\tbytes\tprimeiros_32_hex")
    alvos = ["ConnectServer/ServerList.dat", "Data/MapServerInfo.dat", "Data/MapManager.txt"]
    for t in alvos:
        p = os.path.join(root, t)
        if not os.path.isfile(p):
            print(f"{t}\tAUSENTE\t-")
            continue
        with open(p, "rb") as f:
            d = f.read(32)
        print(f"{t}\t{os.path.getsize(p)}\t{d.hex()}")


def db_backups(root: str) -> None:
    bloco("db_backups (somente cabeçalho; nenhuma restauração)")
    print("arquivo\tbytes\tprimeiros_4_ascii\tprimeiros_16_hex\tsha256_16")
    d0 = os.path.join(root, "DB")
    if not os.path.isdir(d0):
        print("# DB/ ausente")
        return
    for fn in sorted(os.listdir(d0)):
        p = os.path.join(d0, fn)
        if not os.path.isfile(p):
            continue
        with open(p, "rb") as f:
            h = f.read(16)
        head = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                head.update(chunk)
        # decode('latin-1') de um BOM UTF-16 injeta bytes de controle na saida TSV;
        # tudo que nao for imprimivel vira escape, senao o relatorio vira arquivo binario.
        cab = "".join(chr(c) if 0x20 <= c < 0x7f else f"\\x{c:02x}" for c in h[:4])
        print(f"DB/{fn}\t{os.path.getsize(p)}\t{cab}\t{h.hex()}\t"
              f"{head.hexdigest()[:16]}")


def ferramentas_lua(root: str) -> None:
    bloco("ferramentas_lua (arquivos com 'luaenc' no nome; .enc puro nao existe no pacote)")
    print("arquivo\tbytes\tprimeiros_16_hex\tparece_texto_lua")
    n = 0
    for dp, _, fns in os.walk(root):
        for fn in sorted(fns):
            if "luaenc" not in fn.lower():
                continue
            p = os.path.join(dp, fn)
            with open(p, "rb") as f:
                h = f.read(64)
            txt = int(h.lstrip()[:2] in (b"--", b"fu", b"lo", b"re", b"if", b"do", b"en", b"el"))
            print(f"{os.path.relpath(p, root)}\t{os.path.getsize(p)}\t{h[:16].hex()}\t{txt}")
            n += 1
    print(f"# total={n}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--so", default="", help="restringe o inventario a um subdiretorio")
    a = ap.parse_args()
    root = os.environ.get("MU_REF_DATA", "").strip()
    if not root or not os.path.isdir(root):
        print("data_probe: MU_REF_DATA nao definido ou nao e um diretorio", file=sys.stderr)
        return 2
    inventario(root, a.so)
    lua_stats(root)
    dados_texto(root)
    binarios_config(root)
    db_backups(root)
    ferramentas_lua(root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
