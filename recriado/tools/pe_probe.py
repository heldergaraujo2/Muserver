#!/usr/bin/env python3
"""pe_probe.py — inspeção reproduzível de executáveis PE da referência (fase R-5).

Somente leitura. Saída determinística: caminhos relativos a MU_REF_DATA, ordenados, sem
timestamp de execução e sem caminho absoluto do host. Nada aqui é interpretado além do que a
especificação PE define; o que for inferência sai marcado como HIPOTESE no relatório, não aqui.

Uso:
  MU_REF_DATA=/caminho/MuServer python3 tools/pe_probe.py [--ext .exe,.dll] [--keywords]
Saída: TSV em stdout (uma linha por arquivo), mais um bloco de palavras-chave com --keywords.
Código de saída: 0 se todo arquivo listado foi classificado; 1 se algum não é PE; 2 erro de uso.
"""
import argparse
import hashlib
import math
import os
import struct
import sys

MACHINES = {0x014C: "i386", 0x8664: "x86_64", 0x01C0: "arm", 0xAA64: "arm64"}
SUBSYS = {1: "native", 2: "gui", 3: "console", 7: "posix-console"}

# Palavras que interessam ao protocolo/rede. Procurar é medir; achar não é concluir, e não achar
# não prova ausência (pode estar ofuscado, comprimido ou montado em tempo de execução).
KEYWORDS = [
    b"PacketSize", b"HEAD_SIZE", b"HeadSize", b"opcode", b"Opcode", b"Recv", b"Send",
    b"WSARecv", b"WSASend", b"connect", b"listen", b"accept", b"select", b"IOCP",
    b"CreateIoCompletionPort", b"ConnectServer", b"DataServer", b"JoinServer", b"GameServer",
    b"ProtocolCore", b"Lua", b"luaL_", b"55557", b"44406", b"55960", b"55970",
]


def entropy(b: bytes) -> float:
    if not b:
        return 0.0
    freq = [0] * 256
    for x in b:
        freq[x] += 1
    n = len(b)
    e = 0.0
    for c in freq:
        if c:
            p = c / n
            e -= p * math.log2(p)
    return round(e, 4)


def parse_pe(path: str):
    """Devolve dict com campos medidos, ou None se o arquivo não for PE."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 0x40 or data[:2] != b"MZ":
        return None
    (e_lfanew,) = struct.unpack_from("<I", data, 0x3C)
    if e_lfanew + 24 > len(data) or data[e_lfanew:e_lfanew + 4] != b"PE\x00\x00":
        return None
    coff = e_lfanew + 4
    machine, nsec, tstamp, _p2sym, _nsym, optsize, chars = struct.unpack_from("<HHIIIHH", data, coff)
    opt = coff + 20
    if opt + 2 > len(data):
        return None
    (magic,) = struct.unpack_from("<H", data, opt)
    pe32plus = magic == 0x20B
    if opt + (240 if pe32plus else 224) > len(data):
        return None
    if pe32plus:
        entry, imagebase = struct.unpack_from("<IQ", data, opt + 16)
        subsystem = struct.unpack_from("<H", data, opt + 68)[0]
        dd = opt + 112
    else:
        entry, imagebase = struct.unpack_from("<II", data, opt + 16)
        subsystem = struct.unpack_from("<H", data, opt + 68)[0]
        dd = opt + 96
    # diretórios de dados: 1 = exports, 2 = imports (RVA/tamanho)
    exp_rva, exp_sz = struct.unpack_from("<II", data, dd)
    imp_rva, imp_sz = struct.unpack_from("<II", data, dd + 8)
    secs = []
    so = opt + optsize
    for i in range(nsec):
        off = so + i * 40
        if off + 40 > len(data):
            break
        name = data[off:off + 8].rstrip(b"\x00").decode("latin-1", "replace")
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
        blob = data[rawptr:rawptr + rawsize] if rawptr + rawsize <= len(data) else b""
        secs.append((name, vsize, rawsize, entropy(blob)))
    return {
        "tamanho": len(data),
        "sha256_16": hashlib.sha256(data).hexdigest()[:16],
        "maquina": MACHINES.get(machine, hex(machine)),
        "secoes": nsec,
        "timestamp_pe": tstamp,          # campo do arquivo, não da execução: determinístico
        "entry": entry,
        "imagebase": imagebase,
        "subsystem": SUBSYS.get(subsystem, str(subsystem)),
        "pe32plus": int(pe32plus),
        "tem_exports": int(exp_sz > 0),
        "tabela_imports_bytes": imp_sz,
        "entropia_media": round(sum(s[3] for s in secs) / len(secs), 4) if secs else 0.0,
        "lista_secoes": ",".join(s[0] for s in secs),
        "_data": data,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ext", default=".exe")
    ap.add_argument("--keywords", action="store_true")
    ap.add_argument("--limit-keywords", type=int, default=0, help="0 = todos os arquivos")
    a = ap.parse_args()
    root = os.environ.get("MU_REF_DATA", "").strip()
    if not root or not os.path.isdir(root):
        print("pe_probe: MU_REF_DATA nao definido ou nao e um diretorio", file=sys.stderr)
        return 2
    exts = tuple(e.strip().lower() for e in a.ext.split(",") if e.strip())
    files = []
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn.lower().endswith(exts):
                files.append(os.path.join(dp, fn))
    files.sort()
    print("arquivo\ttamanho\tsha256_16\tmaquina\tpe32plus\tsecoes\tentropia_media\t"
          "subsystem\ttem_exports\ttabela_imports_bytes\ttimestamp_pe\tlista_secoes")
    bad = 0
    parsed = []
    for p in files:
        rel = os.path.relpath(p, root)
        info = parse_pe(p)
        if info is None:
            bad += 1
            print(f"{rel}\tNAO-PE\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-")
            continue
        parsed.append((rel, info))
        print(f"{rel}\t{info['tamanho']}\t{info['sha256_16']}\t{info['maquina']}\t{info['pe32plus']}"
              f"\t{info['secoes']}\t{info['entropia_media']}\t{info['subsystem']}\t{info['tem_exports']}"
              f"\t{info['tabela_imports_bytes']}\t{info['timestamp_pe']}\t{info['lista_secoes']}")
    if a.keywords:
        print("\n# ocorrencias de palavras-chave (achar nao e concluir; nao achar nao prova ausencia)")
        print("arquivo\tsha256_16\tpalavra\tocorrencias")
        alvo = parsed if a.limit_keywords <= 0 else parsed[:a.limit_keywords]
        for rel, info in alvo:
            data = info["_data"]
            for kw in KEYWORDS:
                c = data.count(kw)
                if c:
                    print(f"{rel}\t{info['sha256_16']}\t{kw.decode()}\t{c}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
