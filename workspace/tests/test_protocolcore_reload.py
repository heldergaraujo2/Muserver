#!/usr/bin/env python3
"""
Teste de regressao do ProtocolCore: simula o ciclo real de /reload.

Modelo da simulacao (fie ao que o GameServer faz):
  * ProtocolCore.lua e carregado UMA vez no boot -> seu `local
    GameServerProtocol_Handles` persiste para sempre.
  * Scripts em Scripts/ sao recarregados N vezes; cada recarga REDEFINE a
    funcao handler (nova closure, mesmo arquivo:linha) e a registra de novo.

O que este teste mede, de forma observavel, sem inspecionar internos:
  - quantas vezes um handler e invocado por pacote (o original acumula)
  - qual versao do handler executa (o original mantem as obsoletas vivas)
  - se um handler quebrado (error()) ou nil derruba o dispatch

Uso: python3 workspace/tests/test_protocolcore_reload.py
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PRISTINE = os.path.join(ROOT, "workspace", "changes", "originals", "ProtocolCore.lua")
INPLACE = os.path.join(ROOT, "MuServer", "Data", "Script", "System", "ProtocolCore.lua")


def _baseline():
    """Sempre compara contra a copia pristine: o arquivo em MuServer/ ja recebe o
    patch, entao usalo como 'original' tornaria o teste trivialmente verdadeiro."""
    return PRISTINE if os.path.exists(PRISTINE) else INPLACE
PATCH_ALT = os.path.join(ROOT, "workspace", "changes", "patches", "ProtocolCore.lua")
PATCH = os.path.join(ROOT, "MuServer", "Data", "Script", "System", "ProtocolCore.lua")
if not os.path.exists(PATCH):
    PATCH = PATCH_ALT

import lupa

BOOT = """
if not table.unpack then table.unpack = unpack end
ClearPacket = function(n) CLEAR = (CLEAR or 0) + 1 end
LogColor = function(c,s) LOGS = LOGS or {}; LOGS[#LOGS+1] = tostring(s) end
LogPrint = function(s) LOGS = LOGS or {}; LOGS[#LOGS+1] = tostring(s) end
VERSIONS = {}
BridgeFunctionAttach = function() end -- ProtocolCore chama na carga; o bridge real esta em ScriptCore
"""

# Este texto e executado N vezes simulando N reloads. Como e sempre o mesmo
# chunk com o mesmo nome, o `linedefined` do handler e identico: e exatamente a
# condicao que faz o dedupe por identidade de referencia falhar.
SCRIPT = """
local Counter = (MAXV or 0) + 1
MAXV = Counter
VERSIONS[Counter] = 0
function GlobalHandler()
    VERSIONS[Counter] = VERSIONS[Counter] + 1
    return false
end
ProtocolFunctions.GameServerProtocol(GlobalHandler)
"""


def build(core_src, reloads, broken=False):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    rt.execute(BOOT)
    rt.execute(core_src)
    for i in range(reloads):
        rt.execute(SCRIPT)
    if broken:
        rt.execute('ProtocolFunctions.GameServerProtocol(function() error("handler podre") end)')
    return rt, g


def invocations(rt, g):
    rt.execute("GameServerProtocolRecv(1, 12, 'PKT')")
    total = 0
    for k in range(1, int(rt.eval("MAXV or 0")) + 1):
        v = rt.eval("VERSIONS[%d]" % k)
        total += int(v)
    return total


def main():
    fails = []
    n = 0
    print("# ProtocolCore: teste de acumulo por reload")
    orig = open(_baseline(), encoding="utf-8").read()
    pat = open(PATCH, encoding="utf-8").read()

    for reloads in (1, 3, 10):
        n += 1
        rt, g = build(orig, reloads)
        o = invocations(rt, g)
        n += 1
        rt, g = build(pat, reloads)
        p = invocations(rt, g)
        expected_patch = 1
        ok = (p == expected_patch)
        print("%s %d - %d reloads -> invocacoes por pacote: original=%d patch=%d (esperado %d)" % (
            "ok" if ok else "not ok", n, reloads, o, p, expected_patch))
        if not ok:
            fails.append("patch com %d reloads produziu %d invocacoes (esperado %d)" % (reloads, p, expected_patch))
        if reloads > 1 and o == reloads:
            print("#   ^ defeito confirmado no ORIGINAL: cresce linearmente com reloads (%d/%d)" % (o, reloads))

    # versao vigente: apos reloads, o handler que deve rodar e o MAIS NOVO
    n += 1
    rt, g = build(pat, 4)
    rt.execute("for i=1,#VERSIONS do VERSIONS[i]=0 end")
    invocations(rt, g)
    newest = int(rt.eval("VERSIONS[MAXV]"))
    older = int(rt.eval("(VERSIONS[1] or 0)"))
    ok = (newest >= 1 and older == 0)
    print("%s %d - apos 4 reloads executa apenas a versao mais nova (nova=%d antiga=%d)" % (
        "ok" if ok else "not ok", n, newest, older))
    if not ok:
        fails.append("selecao de versao errada: nova=%d antiga=%d" % (newest, older))

    # handler quebrado nao derruba o dispatch
    for tag, src in (("original", orig), ("patch", pat)):
        n += 1
        rt, g = build(src, 2, broken=True)
        try:
            rt.execute("GameServerProtocolRecv(1, 12, 'PKT')")
            survived = True
        except Exception as e:  # noqa
            survived = False
        expect = (tag == "patch")
        print("%s %d - handler que lanca error() nao aborta o dispatch [%s]: %s" % (
            "ok" if survived == expect else "not ok", n, tag,
            "sobreviveu" if survived else "abortou"))
        if tag == "original" and survived:
            fails.append("esperava-se que o ORIGINAL abortasse com handler quebrado")
        if tag == "patch" and not survived:
            fails.append("o PATCH ainda aborta com handler quebrado")

    # ClearPacket continua sendo chamado no caminho nao tratado
    for tag, src in (("original", orig), ("patch", pat)):
        n += 1
        rt, g = build(src, 1)
        rt.execute("GameServerProtocolRecv(1, 12, 'PKT')")
        c = int(rt.eval("CLEAR or 0"))
        ok = (c == 1)
        print("%s %d - ClearPacket chamado exatamente 1x no caminho sem consumo [%s] (=%d)" % (
            "ok" if ok else "not ok", n, tag, c))
        if not ok:
            fails.append("ClearPacket mudou de comportamento em %s: %d" % (tag, c))

    print()
    print("1..%d" % n)
    if fails:
        print("# FALHAS: %d" % len(fails))
        for f in fails:
            print("#   " + f)
        return 1
    print("# TUDO OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
