#!/usr/bin/env python3
"""
Leitor de PE32/PE32+ correto (sem dependencias).
Layout verificado:
  e_lfanew @0x3C ; 'PE\0\0' @e
  IMAGE_FILE_HEADER em e+4: Machine(u16) NumSec(u16) TimeDate(u32) PtrSym(u32)
      NumSym(u32) SizeOfOptionalHeader(u16 @e+20) Characteristics(u16 @e+22)
  OptionalHeader em e+24
  Section headers em e+24+SizeOfOptionalHeader, 40 bytes cada:
      Name[8] VirtualSize(u32@8) VirtualAddress(u32@12) SizeOfRawData(u32@16)
      PointerToRawData(u32@20) ... Characteristics(u32@36)
Uso: python3 pe.py <info|sections|imports|disasm> <arquivo> [rva]
"""
import struct
import sys
import os

MACHINE = {0x14C: "x86", 0x8664: "x64", 0x1C0: "ARM", 0xAA64: "ARM64"}
CHAR = {
    0x0001: "RELOCS_STRIPPED", 0x0002: "EXECUTABLE_IMAGE", 0x0004: "LINE_NUMS_STRIPPED",
    0x0008: "LOCAL_SYMS_STRIPPED", 0x0020: "LARGE_ADDRESS_AWARE", 0x0040: "16BIT_MACHINE",
    0x0080: "NET_RUN_FROM_SWAP", 0x0100: "32BIT_MACHINE", 0x0200: "DEBUG_STRIPPED",
    0x0400: "REM_RUNNABLE_SWAP", 0x1000: "SYSTEM", 0x2000: "DLL", 0x4000: "UP_SYSTEM_ONLY",
    0x0080 | 0x8000: "BYTES_REVERSED_LO", 0x0080: "NET_RUN_FROM_SWAP",
}
DLLCHAR = {0x0001: "HIGH_ENTROPY_VA", 0x0020: "DYNAMIC_BASE(ASLR)", 0x0040: "FORCE_INTEGRITY",
           0x0080: "NX_COMPAT", 0x0100: "IS_DLL", 0x0200: "UNSAFE_BUFFER_TERMINATED",
           0x0400: "NO_SEH", 0x0800: "NO_BIND", 0x1000: "APPCONTAINER",
           0x2000: "WDM_DRIVER", 0x4000: "GUARD_CF", 0x8000: "TERMINAL_SERVER_AWARE"}
SECFL = {0x00000020: "CODE", 0x00000040: "IDATA", 0x00000080: "UDATA",
         0x02000000: "DISCARDABLE", 0x04000000: "NOT_CACHED", 0x08000000: "SHARED",
         0x10000000: "EXECUTE", 0x20000000: "READ", 0x40000000: "WRITE"}
SUBSYS = {1: "Native", 2: "Windows GUI", 3: "Windows CUI", 9: "Windows CE GUI"}
DATADIR = ["EXPORT", "IMPORT", "RESOURCE", "EXCEPTION", "SECURITY", "BASERELOC",
           "DEBUG", "ARCHITECTURE", "GLOBALPTR", "TLS", "LOAD_CONFIG",
           "BOUND_IMPORT", "IAT", "DELAY_IMPORT", "CLR", "RESERVED"]


class PE:
    def __init__(self, path):
        self.path = path
        self.d = open(path, "rb").read()
        d = self.d
        if len(d) < 64 or d[:2] != b"MZ":
            raise ValueError("sem assinatura MZ")
        self.e = struct.unpack_from("<I", d, 0x3C)[0]
        if d[self.e:self.e + 4] != b"PE\x00\x00":
            raise ValueError("sem assinatura PE")
        f = self.e + 4
        self.machine, self.nsec = struct.unpack_from("<HH", d, f)
        self.ts = struct.unpack_from("<I", d, f + 4)[0]
        self.sizeopt, self.chars = struct.unpack_from("<HH", d, f + 16)
        self.opt = self.e + 24
        self.magic = struct.unpack_from("<H", d, self.opt)[0]
        self.p32 = self.magic == 0x10B
        self.secs = []
        so = self.opt + self.sizeopt
        for i in range(self.nsec):
            o = so + i * 40
            if o + 40 > len(d):
                break
            nm = d[o:o + 8].rstrip(b"\x00").decode("latin1", "replace")
            vs, va, rsz, ro = struct.unpack_from("<IIII", d, o + 8)
            fl = struct.unpack_from("<I", d, o + 36)[0]
            self.secs.append(dict(name=nm, vsize=vs, va=va, rawsize=rsz,
                                   rawoff=ro, flags=fl))
        o = self.opt
        base_off = 28 if self.p32 else 24
        self.imagebase = struct.unpack_from("<I" if self.p32 else "<Q", d, o + base_off)[0]
        self.entry = struct.unpack_from("<I", d, o + 16)[0]
        self.sizeimg, self.sizehdr = struct.unpack_from("<II", d, o + 56)
        self.secalign, self.filealign = struct.unpack_from("<II", d, o + 32 if self.p32 else o + 32)
        self.subsys = struct.unpack_from("<H", d, o + 68)[0]
        self.dllchars = struct.unpack_from("<H", d, o + 70)[0]
        self.stackres, self.stackcom, self.heapres, self.heapcom = \
            struct.unpack_from("<IIII", d, o + 72)
        ddo = o + (96 if self.p32 else 112)
        self.ndd = struct.unpack_from("<I", d, ddo - 4)[0]
        self.dd = []
        for i in range(min(self.ndd, 16)):
            self.dd.append(struct.unpack_from("<II", d, ddo + i * 8))

    @property
    def laa(self):
        return bool(self.chars & 0x20)

    def rva2off(self, r):
        for s in self.secs:
            lo = s["va"]
            hi = lo + max(s["vsize"], s["rawsize"])
            if lo <= r < hi and s["rawoff"]:
                if r - lo < s["rawsize"]:
                    return s["rawoff"] + (r - lo)
        return None

    def sec_of(self, r):
        for s in self.secs:
            if s["va"] <= r < s["va"] + max(s["vsize"], s["rawsize"]):
                return s["name"]
        return "?"

    def imports(self):
        dlls = []
        if len(self.dd) < 2 or not self.dd[1][0]:
            return dlls
        io = self.rva2off(self.dd[1][0])
        if io is None:
            return dlls
        k = 0
        while io + k * 20 + 20 <= len(self.d):
            oname, t1, t2, t3, oft = struct.unpack_from("<IIII", self.d, io + k * 20), 0, 0, 0
            oname = struct.unpack_from("<I", self.d, io + k * 20)[0]
            oft = struct.unpack_from("<I", self.d, io + k * 20 + 16)[0]
            if oname == 0 and oft == 0:
                break
            noff = self.rva2off(oname) if oname else None
            name = ""
            if noff:
                end = self.d.find(b"\x00", noff)
                name = self.d[noff:end].decode("latin1", "replace")
            funcs = []
            tbl = oft or (oname + 4)
            toff = self.rva2off(tbl)
            if toff:
                j = 0
                while j < 4000 and toff + j * 4 + 4 <= len(self.d):
                    v = struct.unpack_from("<I", self.d, toff + j * 4)[0]
                    if v == 0:
                        break
                    if not (v & 0x80000000):
                        fo = self.rva2off(v)
                        if fo:
                            nm = self.d[fo + 2:self.d.find(b"\x00", fo + 2)]
                            funcs.append(nm.decode("latin1", "replace"))
                    j += 1
            dlls.append((name, funcs))
            k += 1
            if k > 80:
                break
        return dlls

    def exports(self):
        if not self.dd or not self.dd[0][0]:
            return []
        eo = self.rva2off(self.dd[0][0])
        if eo is None:
            return []
        nmoff, ordinal, nnames = struct.unpack_from("<III", self.d, eo + 12)[:3]
        addr_off = struct.unpack_from("<I", self.d, eo + 20)[0]
        nnames = struct.unpack_from("<I", self.d, eo + 24)[0]
        out = []
        for i in range(min(nnames, 4096)):
            no = self.rva2off(struct.unpack_from("<I", self.d,
                                 self.rva2off(struct.unpack_from("<I", self.d, eo + 32)[0]
                                              + i * 4))[0]) if False else None
            out.append(no)
        return out


def main():
    mode = sys.argv[1]
    p = PE(sys.argv[2])
    if mode == "info":
        print("arquivo        :", p.path)
        print("máquina        :", MACHINE.get(p.machine, hex(p.machine)))
        print("PE             :", "PE32 (0x10B)" if p.p32 else "PE32+ (0x20B)")
        print("TimeDateStamp  :", p.ts, __import__("datetime").datetime.utcfromtimestamp(p.ts).isoformat() if p.ts else "")
        print("Characteristics: 0x%04X" % p.chars,
              " ".join(v for k, v in CHAR.items() if p.chars & k and v not in ("BYTES_REVERSED_LO",)))
        print("LARGEADDRESSAWARE:", "SIM" if p.laa else "NAO  <-- teto de 2GB de espaco de endereco")
        print("SizeOfImage    : %d bytes (%.1f MB)" % (p.sizeimg, p.sizeimg / 1048576))
        print("ImageBase      : 0x%X" % p.imagebase)
        print("EntryPoint RVA : 0x%X [%s]" % (p.entry, p.sec_of(p.entry)))
        print("Subsystem      :", SUBSYS.get(p.subsys, p.subsys))
        print("DllCharacterics: 0x%04X" % p.dllchars,
              " ".join(v for k, v in DLLCHAR.items() if p.dllchars & k))
        print("Stack commit   : %d KB   Heap commit: %d KB" % (p.stackcom // 1024, p.heapcom // 1024))
        print("Seções         :", len(p.secs))
        for s in p.secs:
            print("   %-9s VA=0x%08X VSize=0x%08X Raw=0x%08X RawSize=0x%08X 0x%08X %s" % (
                s["name"], s["va"], s["vsize"], s["rawoff"], s["rawsize"], s["flags"],
                " ".join(v for k, v in SECFL.items() if s["flags"] & k)))
        print("Data dirs      :")
        for i, (r, sz) in enumerate(p.dd):
            if r or sz:
                print("   %-12s RVA=0x%08X size=%d" % (DATADIR[i] if i < len(DATADIR) else i, r, sz))
    elif mode == "imports":
        for name, funcs in p.imports():
            print("%-22s %d importações" % (name, len(funcs)))
            print("    ", ", ".join(funcs[:60]))
    elif mode == "disasm":
        sys.path.insert(0, "/home/user/.venv-tools/lib/python3.11/site-packages")
        from capstone import Cs, CS_ARCH_X86, CS_MODE_32, CS_MODE_64
        md = Cs(CS_ARCH_X86, CS_MODE_32 if p.p32 else CS_MODE_64)
        md.detail = False
        rva = int(sys.argv[3], 0)
        back = int(sys.argv[4]) if len(sys.argv) > 4 else 40
        fwd = int(sys.argv[5]) if len(sys.argv) > 5 else 24
        off = p.rva2off(rva - back)
        if off is None:
            print("RVA 0x%X fora das seções com dados brutos" % rva)
            return
        code = p.d[off:off + back + fwd]
        print("--- %s  RVA 0x%X [%s]  (-%d/+%d bytes) ---" % (
            os.path.basename(p.path), rva, p.sec_of(rva), back, fwd))
        for i in md.disasm(code, rva - back):
            mark = "  <== FALHA" if i.address == rva else ""
            print("  0x%06X: %-24s %s %s%s" % (i.address, i.bytes.hex(), i.mnemonic,
                                               i.op_str, mark))


if __name__ == "__main__":
    main()
