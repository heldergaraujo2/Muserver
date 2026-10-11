#!/usr/bin/env python3
"""
Desassembler de codigo a partir da MEMORIA de um minidump.

Motivo: o GameServer.exe esta protegido com Themida -> o codigo no arquivo .exe
esta criptografado. Mas o dump contem a memoria JA DESACTIVADA/descriptografada
do processo. Assim e possvel inspecionar o fluxo real que executou no momento da
falha, algo impossvel olhando o binario em disco.

Uso: python3 dump_disasm.py <dump.dmp> <offset_rva> [back] [fwd]
"""
import struct
import sys
import json
import os

sys.path.insert(0, "/home/user/.venv-tools/lib/python3.11/site-packages")
from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_MODE_64, CS_ARCH_ARM64


def load_dump(path):
    raw = open(path, "rb").read()
    ns, d = struct.unpack_from("<II", raw, 8)
    S = {}
    for i in range(ns):
        o = d + i * 12
        if o + 12 > len(raw):
            break
        t, dsz, rva = struct.unpack_from("<III", raw, o)
        if t:
            S[t] = (rva, dsz)
    # memoria
    mem = []
    if 5 in S:
        o = S[5][0]
        c = struct.unpack_from("<I", raw, o)[0]
        p = o + 4
        for _ in range(c):
            if p + 16 > len(raw):
                break
            st, dsz, rva = struct.unpack_from("<QII", raw, p)
            if dsz and rva + dsz <= len(raw):
                mem.append((st, dsz, rva))
            p += 16
    if 9 in S and not mem:
        o = S[9][0]
        c = struct.unpack_from("<I", raw, o)[0]
        cur = struct.unpack_from("<Q", raw, o + 4)[0]
        p = o + 12
        for _ in range(c):
            if p + 16 > len(raw):
                break
            st, dsz = struct.unpack_from("<QQ", raw, p)
            mem.append((st, dsz, cur))
            cur += dsz
            p += 16
    # modulos
    mods = []
    if 4 in S:
        o = S[4][0]
        c = struct.unpack_from("<I", raw, o)[0]
        p = o + 4
        for _ in range(c):
            if p + 108 > len(raw):
                break
            base, size, csum, ts, nm = struct.unpack_from("<QIIII", raw, p)
            ln = struct.unpack_from("<I", raw, nm)[0] if 0 < nm < len(raw) - 8 else 0
            name = raw[nm + 4:nm + 4 + ln].decode("utf-16-le", "replace") if ln else "?"
            mods.append(dict(name=os.path.basename(name.replace("\\", "/")), base=base,
                             size=size, end=base + size, ts=ts, full=name))
            p += 108
    return raw, mem, mods


def read_mem(mem, raw, addr, n):
    for s, z, r in mem:
        if s <= addr < s + z:
            avail = min(n, s + z - addr)
            return raw[r + (addr - s): r + (addr - s) + avail]
    return None


def main():
    path = sys.argv[1]
    off = int(sys.argv[2], 0)
    back = int(sys.argv[3]) if len(sys.argv) > 3 else 48
    fwd = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    raw, mem, mods = load_dump(path)
    main = mods[0]
    addr = main["base"] + off
    blob = read_mem(mem, raw, addr - back, back + fwd)
    print("dump          :", path)
    print("modulo        :", main["full"])
    print("base em memor :", "0x%X  size 0x%X" % (main["base"], main["size"]))
    print("RVA pedido    : 0x%X  -> endereco 0x%X" % (off, addr))
    if blob is None:
        print("MEMORIA DA FALHA NAO INCLUIDA no dump (MiniDumpWithoutMemory).")
        print("Regioes capturadas:", len(mem), "total:",
              sum(z for _, z, _ in mem), "bytes")
        return
    mode = CS_MODE_64 if main["size"] > 0xFFFFFFFF or "x64" in str(sys.argv) else CS_MODE_32
    md = Cs(CS_ARCH_X86, mode)
    md.syntax = 0
    print("--- desassemblagem (%d bytes de memoria real do processo) ---" % len(blob))
    ins = list(md.disasm(blob, addr - back))
    for i in ins:
        mark = ""
        if i.address == addr:
            mark = "   <<<<<< INSTRUCAO DA FALHA"
        print("  0x%08X (RVA 0x%06X): %-28s %s" % (
            i.address, i.address - main["base"],
            i.mnemonic + " " + i.op_str, mark))
    if not ins:
        print("  (nenhuma instruvao decodificada - bytes:", blob[:32].hex(), ")")
    # hexdump ao redor
    print("--- hexdump ---")
    for k in range(0, len(blob), 16):
        line = blob[k:k + 16]
        a = addr - back + k
        print("  0x%08X (RVA 0x%06X): %-47s %s" % (a, a - main["base"], line.hex(),
                                                    "".join(chr(c) if 32 <= c < 127 else "." for c in line)))


if __name__ == "__main__":
    main()
