#!/usr/bin/env python3
"""Varre todos os dumps, agrupa por assinatura de falha e desassembla o ponto exato
a partir da memoria do dump (codigo ja descriptografado pelo Themida em runtime)."""
import json
import os
import sys
import struct
import collections

sys.path.insert(0, "/home/user/.venv-tools/lib/python3.11/site-packages")
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dump_disasm import load_dump, read_mem

ROOT = "/home/user/Muserver/"
rep = json.load(open("/home/user/workspace/reports/dumps.json"))
groups = collections.defaultdict(list)
for x in rep:
    e = x.get("exception")
    if not e or not e.get("fault"):
        continue
    key = (e["code_name"], e["fault"])
    groups[key].append(x)

md = Cs(CS_ARCH_X86, CS_MODE_32)
cache = {}


def get(path):
    if path not in cache:
        cache[path] = load_dump(ROOT + path)
    return cache[path]


out = []
for (cn, fault), lst in sorted(groups.items(), key=lambda kv: -len(kv[1])):
    name, _, soff = fault.partition("+")
    off = int(soff, 16)
    out.append("=" * 100)
    out.append("FAMILIA: %s em %s   (%d crash(es))" % (cn, fault, len(lst)))
    ex0 = lst[0]["exception"]
    out.append("  amostras: %s" % ", ".join(os.path.basename(y["file"]) for y in lst[:4]))
    out.append("  regs da amostra: %s" % json.dumps(ex0.get("regs", {})))
    if ex0.get("av_op"):
        out.append("  AV: op=%s target=0x%X class=%s" % (
            ex0["av_op"], ex0.get("av_target", 0), ex0.get("av_class")))
    # tenta desassemblar em qualquer dump do grupo que tenha a memoria
    done = False
    for y in lst:
        try:
            raw, mem, mods = get(y["file"])
        except Exception as ex:
            continue
        base = mods[0]["base"]
        blob = read_mem(mem, raw, base + off - 40, 84)
        if not blob:
            continue
        out.append("  --- codigo real em memoria (%s) ---" % os.path.basename(y["file"]))
        for i in md.disasm(blob, base + off - 40):
            mk = "   <<<<<< FALHA" if i.address == base + off else ""
            out.append("     RVA 0x%06X: %-26s%s" % (i.address - base,
                                                      i.mnemonic + " " + i.op_str, mk))
        done = True
        break
    if not done:
        out.append("  (memoria do ponto de falha nao foi capturada em nenhum dump do grupo)")
    # backtrace consolidado
    seqs = [tuple(b["module"] + "@" + b["offset"] for b in (yy["exception"].get("backtrace") or [])[:6])
            for yy in lst]
    cnt = collections.Counter(seqs)
    out.append("  backtraces mais frequentes:")
    for s, c in cnt.most_common(3):
        out.append("    %dx  %s" % (c, " -> ".join(s)))
txt = "\n".join(out)
open("/home/user/workspace/reports/crash_families.txt", "w").write(txt)
print(txt[:14000])
