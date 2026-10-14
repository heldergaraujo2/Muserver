#!/usr/bin/env python3
"""
Analisador de Windows Minidumps para MuServer (MU Online Season 6.20).

Descoberta técnica importante: os dumps do GameServer usam WOW64_CONTEXT
(dump gravado por um helper 64-bits sobre processo 32-bits), cujo layout difere
do CONTEXT x86 padrão:  Ebp=0xB4, Eip=0xB8, SegCs=0xBC, EFlags=0xC0, Esp=0xC4.
O parser detecta o layout automaticamente validando SegCs == 0x23.

Saída: JSON com exceção, módulo/offset de falha, registradores e backtrace
heurístico (varredura da pilha em busca de endereços de retorno dentro dos módulos).
Sem dependências externas.
"""
import struct
import sys
import os
import json
import datetime

EXCEPTION_CODES = {
    0x80000003: ("DBG_BREAKPOINT", "Breakpoint INT3"),
    0x40010004: ("MSVCPP_EH_UNWIND", "Excecao de fluxo de controle (C++ EH)"),
    0xC0000005: ("ACCESS_VIOLATION", "Acesso a memoria invalida"),
    0xC0000006: ("IN_PAGE_ERROR", "Falha de paginacao de arquivo mapeado"),
    0xC0000008: ("BAD_HANDLE", "Handle invalido"),
    0xC000001D: ("ILLEGAL_INSTRUCTION", "Instrucao ilegal"),
    0xC0000025: ("NONCONTINUEABLE_EXCEPTION", "Excecao nao continuavel"),
    0xC0000094: ("INTEGER_DIVIDE_BY_ZERO", "Divisao inteira por zero"),
    0xC0000095: ("INTEGER_OVERFLOW", "Overflow inteiro"),
    0xC00000FD: ("STACK_OVERFLOW", "Estouro de pilha / recursao"),
    0xC0000374: ("HEAP_CORRUPTION", "Corrupcao de heap"),
    0xC0000379: ("VALIDATION_FAILURE", "Falha de validacao / __fastfail"),
    0xC0000409: ("STACK_BUFFER_OVERRUN", "Stack buffer overrun (/GS)"),
    0xC000041D: ("FILTERED_EXCEPTION", "Excecao nao tratada em filtro"),
    0xE06D7363: ("CPP_EH_EXCEPTION", "Excecao C++ (throw)"),
    0xE0434352: ("CLR_EXCEPTION", "Excecao .NET gerenciada"),
}
AV_OP = {0: "READ", 1: "WRITE", 8: "DEP-EXECUTE"}

# WOW64_CONTEXT (x86 capturado por helper 64-bit)
WOW64_CTX = [("edi", 0x9C), ("esi", 0xA0), ("ebx", 0xA4), ("edx", 0xA8),
             ("ecx", 0xAC), ("eax", 0xB0), ("ebp", 0xB4), ("eip", 0xB8),
             ("segcs", 0xBC), ("eflags", 0xC0), ("esp", 0xC4), ("segss", 0xC8)]
# CONTEXT x86 padrao
X86_CTX = [("edi", 0x9C), ("esi", 0xA0), ("ebx", 0xA4), ("edx", 0xA8),
           ("ecx", 0xAC), ("eax", 0xB0), ("ebp", 0xB4), ("esp", 0xB8),
           ("eip", 0xBC), ("segcs", 0xC0), ("eflags", 0xC4), ("segss", 0xC8)]
X64_CTX = [("rax", 0x78), ("rcx", 0x80), ("rdx", 0x88), ("rbx", 0x90),
           ("rsp", 0x98), ("rbp", 0xA0), ("rsi", 0xA8), ("rdi", 0xB0),
           ("r8", 0xB8), ("r9", 0xC0), ("r10", 0xC8), ("r11", 0xD0),
           ("r12", 0xD8), ("r13", 0xE0), ("r14", 0xE8), ("r15", 0xF0),
           ("rip", 0xF8)]


def parse(path):
    raw = open(path, "rb").read()
    out = {"file": path.replace(os.getcwd() + "/", ""), "bytes": len(raw)}
    if len(raw) < 32 or raw[:4] != b"MDMP":
        out["skip"] = "nao-e-minidump"
        return out

    def u32(o):
        return struct.unpack_from("<I", raw, o)[0] if 0 <= o and o + 4 <= len(raw) else 0

    def u64(o):
        return struct.unpack_from("<Q", raw, o)[0] if 0 <= o and o + 8 <= len(raw) else 0

    def u16(o):
        return struct.unpack_from("<H", raw, o)[0] if 0 <= o and o + 2 <= len(raw) else 0

    ns, drva = u32(8), u32(12)
    S = {}
    for i in range(ns):
        o = drva + i * 12
        if o + 12 > len(raw):
            break
        t, dsz, rva = struct.unpack_from("<III", raw, o)
        if t:
            S[t] = (rva, dsz)

    # ---------- SystemInfo ----------
    is64 = False
    if 7 in S:
        o = S[7][0]
        arch = u16(o)
        is64 = (arch == 9)
        out["os"] = {
            "arch": "x64" if is64 else "x86 (32-bit)",
            "ncpu": raw[o + 6] if o + 6 < len(raw) else 0,
            "windows": "%d.%d build %d" % (u32(o + 8), u32(o + 12), u32(o + 16)),
            "platform": u32(o + 20),
        }

    # ---------- Memory map ----------
    mem = []
    if 5 in S:
        o = S[5][0]
        cnt = u32(o)
        p = o + 4
        for _ in range(cnt):
            if p + 16 > len(raw):
                break
            start, dsz, rva = u64(p), u32(p + 8), u32(p + 12)
            if dsz and rva + dsz <= len(raw):
                mem.append((start, dsz, rva))
            p += 16
    if 9 in S and not mem:
        o = S[9][0]
        cnt = u32(o)
        cur = u64(o + 4)
        p = o + 12
        for _ in range(cnt):
            if p + 16 > len(raw):
                break
            start, dsz = u64(p), u64(p + 8)
            mem.append((start, dsz, cur))
            cur += dsz
            p += 16
    mem.sort()

    def read_mem(addr, size):
        for start, dsz, rva in mem:
            if start <= addr and addr + size <= start + dsz:
                off = rva + (addr - start)
                return raw[off:off + size]
            if start <= addr < start + dsz:  # parcial
                avail = start + dsz - addr
                if avail >= 4:
                    off = rva + (addr - start)
                    return raw[off:off + min(size, avail)]
        return None

    # ---------- Modules ----------
    mods = []
    if 4 in S:
        o = S[4][0]
        cnt = u32(o)
        p = o + 4
        stride = 108
        for _ in range(cnt):
            if p + stride > len(raw):
                break
            base, size, csum, ts, nm_rva = struct.unpack_from("<QIIII", raw, p)
            name = ""
            if 32 < nm_rva < len(raw) - 8:
                ln = u32(nm_rva)
                if 0 < ln < 4096 and nm_rva + 4 + ln <= len(raw):
                    name = raw[nm_rva + 4:nm_rva + 4 + ln].decode("utf-16-le", "replace")
            voff = p + 24
            ver = None
            if voff + 24 <= len(raw) and u32(voff) == 0xFEEF04BD:
                fms, lms = u32(voff + 8), u32(voff + 16)
                ver = "%d.%d.%d.%d" % (fms >> 16, fms & 0xFFFF, lms >> 16, lms & 0xFFFF)
            cvsz, cvrva = u32(p + 76), u32(p + 80)
            pdb = None
            if cvrva and cvrva + 8 <= len(raw) and u32(cvrva) == 0x53445349:  # 'SDSR'
                nmoff = cvrva + 8
                if 0 < nmoff < len(raw):
                    end = raw.find(b"\x00", nmoff)
                    if end > nmoff:
                        pdb = raw[nmoff:end].decode("utf-8", "replace")
            mods.append({"name": os.path.basename(name.replace("\\", "/")) if name else "mod%d" % len(mods),
                         "path": name, "base": base, "size": size, "end": base + size,
                         "ts": ts, "checksum": csum, "ver": ver, "pdb": pdb})
            p += stride

    def owner(a):
        for x in mods:
            if x["base"] <= a < x["end"]:
                return x
        return None

    def fmt(a, mo=None):
        m = mo or owner(a)
        if m:
            return "%s+0x%X" % (m["name"], a - m["base"])
        return "0x%X" % a

    # ---------- Threads ----------
    threads = {}
    if 3 in S:
        o = S[3][0]
        cnt = u32(o)
        p = o + 4
        for _ in range(cnt):
            if p + 48 > len(raw):
                break
            tid = u32(p)
            stk_start, stk_sz = u64(p + 24), u32(p + 32)
            threads[tid] = {"tid": tid, "stack_base": stk_start, "stack_size": stk_sz,
                            "ctx_sz": u32(p + 40), "ctx_rva": u32(p + 44)}
            p += 48
    tnames = {}
    if 24 in S:
        o = S[24][0]
        cnt = u32(o)
        p = o + 4
        for _ in range(cnt):
            if p + 12 > len(raw):
                break
            tid, ln, rva = u32(p), u32(p + 4), u32(p + 8)
            if rva and 0 < ln < 4096 and rva + 4 + ln <= len(raw):
                tnames[tid] = raw[rva + 4:rva + 4 + ln].decode("utf-16-le", "replace")
            p += 12

    # ---------- Exception ----------
    if 6 in S:
        o = S[6][0]
        tid = u32(o)
        e = o + 8
        code, flags = struct.unpack_from("<II", raw, e)
        rec, addr = struct.unpack_from("<QQ", raw, e + 8)
        npar = u32(e + 24)
        par = [u64(e + 32 + i * 8) for i in range(min(npar, 15))]
        nm, desc = EXCEPTION_CODES.get(code, ("DESCONHECIDO", ""))
        ex = {"thread_id": tid, "code": "0x%08X" % code, "code_name": nm,
              "desc": desc, "address": addr, "fault": fmt(addr),
              "params": ["0x%X" % p for p in par]}
        if code == 0xC0000005 and len(par) >= 2:
            tgt = par[1]
            ex["av_op"] = AV_OP.get(par[0], str(par[0]))
            ex["av_target"] = tgt
            if tgt < 0x10000:
                ex["av_class"] = "NULL_DEREF+offset=0x%X" % tgt
            else:
                m = owner(tgt)
                inside = any(s <= tgt < s + z for s, z, _ in mem)
                ex["av_class"] = ("modulo %s" % m["name"]) if m else (
                    "heap/stack valido (use-after-free ou buffer)" if inside
                    else "fora do mapa de memoria (ponteiro corrompido/solto)")
        # contexto: detectar WOW64 vs padrao
        csz, crva = struct.unpack_from("<II", raw, e + 152)
        regs = {}
        layout = None
        if crva and crva + csz <= len(raw):
            for cand, tagname in ((WOW64_CTX, "wow64"), (X86_CTX, "x86")):
                tbl = dict(cand)
                if not is64 and raw and u32(crva + tbl["segcs"]) == 0x23:
                    layout = tagname
                    for k, off in cand:
                        regs[k] = u32(crva + off)
                    break
            if layout is None:
                tbl = dict(X64_CTX) if is64 else dict(X86_CTX)
                layout = "x64" if is64 else "x86?"
                for k, off in (X64_CTX if is64 else X86_CTX):
                    regs[k] = u64(crva + off) if is64 else u32(crva + off)
        ex["ctx_layout"] = layout
        ex["regs"] = {k: "0x%X" % v for k, v in regs.items()}
        if regs.get("eip") == addr or regs.get("rip") == addr:
            ex["eip_matches_exception_address"] = True
        ex["main_module"] = mods[0]["name"] if mods else None

        # backtrace heuristico a partir de ESP
        sp = regs.get("esp", regs.get("rsp"))
        bt = []
        if sp:
            blob = read_mem(sp, 0x2000)
            if blob:
                seen = set()
                for i in range(0, len(blob) - 4, 4):
                    v = struct.unpack_from("<Q" if is64 else "<I", blob, i)[0]
                    m = owner(v)
                    if not m:
                        continue
                    key = (m["name"], v - m["base"])
                    if key in seen:
                        continue
                    # filtro: precisa parecer retorno de chamada (dentro de .text)
                    seen.add(key)
                    bt.append({"sp_off": i, "module": m["name"],
                               "offset": "0x%X" % (v - m["base"])})
                    if len(bt) >= 250:
                        break
        ex["backtrace"] = bt[:80]
        ex["n_backtrace"] = len(bt)
        th = threads.get(tid)
        if th:
            ex["stack_used"] = (th["stack_base"] + th["stack_size"]) - sp if sp else None
            ex["stack_region"] = th["stack_size"]
        out["exception"] = ex
    else:
        out["note"] = "sem ExceptionStream"

    out["n_threads"] = len(threads)
    if tnames:
        out["thread_names"] = tnames
    out["n_modules"] = len(mods)
    out["n_mem_ranges"] = len(mem)
    # faixa de endereco do processo -> diagnostico de espaco de enderecamento 32-bit
    if mods:
        lo = min(m["base"] for m in mods)
        hi = max(m["end"] for m in mods)
        out["addr_space"] = {"lowest": "0x%X" % lo, "highest": "0x%X" % hi,
                             "image_total": sum(m["size"] for m in mods)}
        out["main_image_size"] = mods[0]["size"]
        out["main_image_ts"] = datetime.datetime.utcfromtimestamp(
            mods[0]["ts"]).strftime("%Y-%m-%dT%H:%M:%SZ") if mods[0]["ts"] else None
        out["main_pdb"] = mods[0]["pdb"]
        third = [m["name"] for m in mods if not m["name"].lower().startswith(
            ("ntdll", "kernel", "user32", "gdi32", "advapi", "ws2_32", "msvc", "ole",
             "shell", "rpcrt", "secur", "winhttp", "dnsapi", "imm32", "lpk", "usp10",
             "dwrite", "comdlg", "version", "wldap", "samlib", "sspicli", "gpapi",
             "crypt", "ncrypt", "msasn1", "wininet", "urlmon", "ieframe", "propsys",
             "shlwapi", "clbcat", "ole32", "oleaut32", "authip", "napinsp", "pnrp",
             "fwpu", "wship6", "wshtcpip", "wspapi", "msctf", "ctfmon", "srvcli",
             "netapi32", "samcli", "avRT", "profapi", "devobj", "cfgmgr", "setupapi",
             "dpapi", "winnsi", "iphlpapi", "amsi", "userenv", "wldp", "bcrypt",
             "kernelbase", "kernel32", "combase", "gdi32", "win32u", "sechost",
             "pdh", "psapi", "dbghelp", "dbmodel", "plt", "qwave", "audiods"))]
        out["non_system_modules"] = third
    return out


def main():
    res = []
    for f in sys.argv[1:]:
        try:
            res.append(parse(f))
        except Exception as e:
            import traceback
            res.append({"file": f, "error": "%s: %s" % (type(e).__name__, e),
                        "tb": traceback.format_exc()[-500:]})
    json.dump(res, sys.stdout, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
