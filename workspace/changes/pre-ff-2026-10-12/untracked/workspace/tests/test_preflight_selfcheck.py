#!/usr/bin/env python3
"""
Autoteste das ferramentas de auditoria (o teste do teste).

Por que existe: um validador que gera falso positivo em massa e pior do que nenhum
validador - a primeira versao do check P04 marcou 1113/1113 linhas de spawn como
invalidas porque assumiu um unico formato de arquivo, quando MonsterSetBase tem
DOIS formatos (NPCS 6 colunas / SPOTS 8 colunas) alternados por uma linha de
secao. Este teste congela o comportamento correto.

Cobre: parser de INI, detector de formatos do MonsterSetBase, leitor de PE, e o
parser de minidump contra um dump REAL do repositorio (teste dourado - os offsets
WOW64_CONTEXT custaram a descoberta central da auditoria e nao podem regredir).

Uso: python3 workspace/tests/test_preflight_selfcheck.py
"""
import os
import sys
import tempfile
import shutil

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "workspace", "tools"))

import muserver_preflight as pf  # noqa

fails = []
n = 0


def check(name, cond, detail=""):
    global n
    n += 1
    print("%s %d - %s%s" % ("ok" if cond else "not ok", n, name,
                            ("   # " + str(detail)) if (detail and not cond) else ""))
    if not cond:
        fails.append("%s  %s" % (name, detail))


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(text, (bytes, bytearray)) else "w"
    with open(path, mode, **({} if mode == "wb" else {"newline": ""})) as f:
        f.write(text)


def test_ini():
    txt = ("//##### cabecalho\n"
           "[GameServerInfo]\n"
           "ServerName = Geral ; comentario\n"
           "ServerPort = 55901\n"
           "; linha comentada\n"
           "DataServerPort = 55960\n")
    cfg = pf.parse_ini(txt)
    check("parse_ini le chave/valor da secao", cfg[("GameServerInfo", "ServerName")] == "Geral")
    check("parse_ini remove comentario de fim de linha",
          cfg[("*", "ServerName")] == "Geral", repr(cfg[("*", "ServerName")]))
    check("parse_ini aceita espaco no nome da chave", cfg[("*", "ServerPort")] == "55901")
    check("parse_ini ignora linhas ; e //", ("*", "linha") not in cfg)
    check("as_int aceita decimal e hex",
          pf.as_int("55901") == 55901 and pf.as_int("0x20") == 32)
    check("as_int devolve None para valor nao numerico", pf.as_int("abc") is None)


def test_monstersets():
    tmp = tempfile.mkdtemp(prefix="preflight-")
    try:
        msn = os.path.join(tmp, "Data", "MonsterSetBase", "000 - Teste.txt")
        w(msn,
          "//comentario\n"
          "0\n"
          "//Monster MapNumber Range PositionX PositionY Direction Comment\n"
          "001  00  4  100  100  0  //npc valido\n"
          "002  00  4  999  100  0  //X fora de 0..255\n"
          "1\n"
          "//Monster Map Range BeginX BeginY EndX EndY Direction Quantity Comment\n"
          "003  00  4  50  50  60  60  0  5  //spot valido\n"
          "004  00  4  60  50  50  60  0  5  //BeginX > EndX\n")
        w(os.path.join(tmp, "Data", "Terrain", "Terrain0.att"),
          bytes([0, 255, 255]) + bytes(256 * 256))
        pf.results.clear()
        r = pf.check_monstersets(tmp)
        check("P04 conta as 4 linhas de dados (2 formatos)",
              r["lines"] == 4, r)
        check("P04 nao produz linhas malformadas no fixture limpo", r.get("malformed") == 0, r)
        check("P04 marca exatamente os 2 defeitos reais, nao as linhas validas",
              r["bad_geometry"] == 2, r)
        w(msn, "0\n//h\n001  00  4  100  100  0  //ok\n002  00  4  12  8  3  //ok\n")
        pf.results.clear()
        r2 = pf.check_monstersets(tmp)
        check("P04 com arquivo integro produz zero defeitos (anti falso positivo)",
              r2["bad_geometry"] == 0 and r2["lines"] == 2, r2)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_pe():
    from pe import PE
    gs = os.path.join(ROOT, "MuServer", "GameServer", "GameServer.exe")
    if not os.path.exists(gs):
        check("pe.py: GameServer.exe ausente - pulado", True)
        return
    pe = PE(gs)
    check("pe.py: identifica x86 (0x14C)", pe.machine == 0x14C, hex(pe.machine))
    check("pe.py: SizeOfImage coerente com o inventario (40..60 MB)",
          40 * 1048576 < pe.sizeimg < 60 * 1048576, pe.sizeimg)
    check("pe.py: Characteristics tem EXECUTABLE_IMAGE", bool(pe.chars & 0x0002), hex(pe.chars))
    check("pe.py: LAA ausente (achado P01 - nao pode virar 'sim' por engano)",
          pe.laa is False, pe.chars)
    check("pe.py: detecta Themida pela secao .themida",
          ".themida" in {s["name"] for s in pe.secs}, [s["name"] for s in pe.secs])
    check("pe.py: rva2off traduz o entrypoint para offset de arquivo",
          pe.rva2off(pe.entry) is not None)


GOLDEN = {
    "file": "MuServer/GameServer/2026-8-15_0h37m35s.dmp",
    "code": "0xC0000005",
    "code_name": "ACCESS_VIOLATION",
    "fault": "GameServer.exe+0xBEBA2",
    "ctx_layout": "wow64",
    "av_op": "READ",
    "n_modules": 57,
    "eip": "0x135EBA2",
    "segcs": "0x23",
    "segss": "0x2B",
}


def test_minidump_golden():
    p = os.path.join(ROOT, GOLDEN["file"])
    if not os.path.exists(p):
        check("minidump: dump de referencia ausente - pulado", True)
        return
    import minidump_analyze as ma
    res = ma.parse(p)
    e = res.get("exception", {})
    for k, expect in (("code", GOLDEN["code"]), ("code_name", GOLDEN["code_name"]),
                      ("fault", GOLDEN["fault"]), ("ctx_layout", GOLDEN["ctx_layout"]),
                      ("av_op", GOLDEN["av_op"])):
        check("minidump golden: %s == %s" % (k, expect), e.get(k) == expect, e.get(k))
    check("minidump golden: 57 modulos", res.get("n_modules") == GOLDEN["n_modules"],
          res.get("n_modules"))
    regs = e.get("regs", {})
    check("minidump golden: Eip bate com ExceptionAddress (prova o layout WOW64)",
          regs.get("eip") == GOLDEN["eip"], regs.get("eip"))
    check("minidump golden: SegCs=0x23 e SegSs=0x2B",
          regs.get("segcs") == GOLDEN["segcs"] and regs.get("segss") == GOLDEN["segss"], regs)
    check("minidump golden: Eip lido do contexto e o mesmo do registro de excecao",
          int(regs.get("eip", "0"), 16) == e.get("address"), (regs.get("eip"), e.get("address")))


if __name__ == "__main__":
    print("# autoteste: preflight, pe, minidump")
    test_ini()
    test_monstersets()
    test_pe()
    test_minidump_golden()
    print()
    print("1..%d" % n)
    if fails:
        print("# FALHAS: %d" % len(fails))
        for f in fails:
            print("#   " + f)
        sys.exit(1)
    print("# autoteste OK")
