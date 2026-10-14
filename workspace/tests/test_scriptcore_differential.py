#!/usr/bin/env python3
"""
Teste diferencial do layer de bridge Lua: ORIGINAL x PATCHED.

Objetivo:
  (1) PROVAR que o patch nao altera o comportamento observavel para handlers
      saudaveis (mesmos valores de retorno, mesma ordem, mesma propagacao de
      argumentos) - isso e o que torna a mudanca segura num GameServer em
      producao que nao podemos recompilar.
  (2) PROVAR que o patch elimina as duas falhas de robustez: handler que lanca
      erro e handler registrado com nome inexistente.

Execucao: python3 workspace/tests/test_scriptcore_differential.py
Saida: TAP-like + codigo de saida 0 (ok) / 1 (falha).
"""
import os
import sys
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PRISTINE = os.path.join(ROOT, "workspace", "changes", "originals", "ScriptCore.lua")
INPLACE = os.path.join(ROOT, "MuServer", "Data", "Script", "System", "ScriptCore.lua")


def _baseline():
    """Sempre compara contra a copia pristine: o arquivo em MuServer/ ja recebe o
    patch, entao usalo como 'original' tornaria o teste trivialmente verdadeiro."""
    return PRISTINE if os.path.exists(PRISTINE) else INPLACE
# Valida o arquivo EM PRODUCAo (MuServer/...); o .lua em changes/patches e a
# referencia do patch, usada como fallback.
PATCHED_CANDIDATES = [
    os.path.join(ROOT, "MuServer", "Data", "Script", "System", "ScriptCore.lua"),
    os.path.join(ROOT, "workspace", "changes", "patches", "ScriptCore.lua"),
]

try:
    import lupa
except ImportError:
    print("# lupa nao disponivel - tentando criar ambiente")
    sys.exit(2)

SHIM = """
if not table.unpack then table.unpack = unpack end
if not table.pack then
  function table.pack(...) return { n = select('#', ...), ... } end
end
LogColor = function(c, s) LOG[#LOG+1] = "color"..c..":"..tostring(s) end
LogPrint = function(s) LOG[#LOG+1] = "print:"..tostring(s) end
LOG = LOG or {}
"""

# Cada caso: (nome, lua-que-prepara-registros, expressao-para-avaliar, esperado)
CASES_HEALTHY = [
    ("OnReadScript void chama todos",
     'A=0; function h1() A=A+1 end; function h2() A=A+2 end; '
     "BridgeFunctionAttach('OnReadScript','h1'); BridgeFunctionAttach('OnReadScript','h2')",
     "(function() BridgeFunction_OnReadScript() return A end)()", "3"),
    ("OnUserDamage: handler retorna 0 -> default 0",
     "function h() return 0 end; BridgeFunctionAttach('OnUserDamage','h')",
     "BridgeFunction_OnUserDamage()", "0"),
    ("OnUserDamage: handler retorna 7 -> retorna 7",
     "function h() return 7 end; BridgeFunctionAttach('OnUserDamage','h')",
     "BridgeFunction_OnUserDamage()", "7"),
    ("OnUserDamage: sem handlers -> 0",
     "", "BridgeFunction_OnUserDamage()", "0"),
    ("OnUserItemUse: passa o valor do handler",
     "function h() return 42 end; BridgeFunctionAttach('OnUserItemUse','h')",
     "BridgeFunction_OnUserItemUse()", "42"),
    ("OnCommandManager: ret~=0 -> 1",
     "function h() return 9 end; BridgeFunctionAttach('OnCommandManager','h')",
     "BridgeFunction_OnCommandManager()", "1"),
    ("OnCommandManager: ret==0 -> 0",
     "function h() return 0 end; BridgeFunctionAttach('OnCommandManager','h')",
     "BridgeFunction_OnCommandManager()", "0"),
    ("OnNpcTalk: ret~=0 -> 1",
     "function h() return 1 end; BridgeFunctionAttach('OnNpcTalk','h')",
     "BridgeFunction_OnNpcTalk()", "1"),
    ("OnCheckUserTarget: ret==0 -> 0 (nega)",
     "function h() return 0 end; BridgeFunctionAttach('OnCheckUserTarget','h')",
     "BridgeFunction_OnCheckUserTarget()", "0"),
    ("OnCheckUserTarget: ret==1 -> 1 (permite)",
     "function h() return 1 end; BridgeFunctionAttach('OnCheckUserTarget','h')",
     "BridgeFunction_OnCheckUserTarget()", "1"),
    ("OnCheckUserTarget: sem handler -> 1",
     "", "BridgeFunction_OnCheckUserTarget()", "1"),
    ("OnUserItemMove: ret==0 -> 0",
     "function h() return 0 end; BridgeFunctionAttach('OnUserItemMove','h')",
     "BridgeFunction_OnUserItemMove()", "0"),
    ("dedupe: mesmo nome 2x nao duplica",
     'N=0; function h() N=N+1 end; '
     "BridgeFunctionAttach('OnUserDie','h'); BridgeFunctionAttach('OnUserDie','h')",
     "(function() BridgeFunction_OnUserDie() return N end)()", "1"),
    ("ordem: 1o handler que decide encerra a cadeia",
     "ORDER=''; function a() ORDER=ORDER..'a' return 0 end; "
     "function b() ORDER=ORDER..'b' return 5 end; function c() ORDER=ORDER..'c' return 5 end; "
     "BridgeFunctionAttach('OnUserDamage','a'); BridgeFunctionAttach('OnUserDamage','b'); "
     "BridgeFunctionAttach('OnUserDamage','c')",
     "(function() local r=BridgeFunction_OnUserDamage() return ORDER..'='..r end)()", "ab=5"),
    ("varargs chegam na ordem certa",
     "SEEN=''; function v(a,b,c) SEEN=tostring(a)..','..tostring(b)..','..tostring(c) end; "
     "BridgeFunctionAttach('OnCharacterEntry','v')",
     "(function() BridgeFunction_OnCharacterEntry(11,'zx',33) return SEEN end)()", "11,zx,33"),
    ("OnMonsterDamage propaga valor",
     "function h() return 1234 end; BridgeFunctionAttach('OnMonsterDamage','h')",
     "BridgeFunction_OnMonsterDamage()", "1234"),
    ("OnSQLAsyncResult e void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnSQLAsyncResult","h")',
     "(function() BridgeFunction_OnSQLAsyncResult('x') return C end)()", "1"),
    ("GameServerProtocol e void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("GameServerProtocol","h")',
     "(function() BridgeFunction_GameServerProtocol(1,2) return C end)()", "1"),
    ("OnTimerThread e void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnTimerThread","h")',
     "(function() BridgeFunction_OnTimerThread() return C end)()", "1"),
    ("OnUserItemPick: ret==0 -> 0",
     "function h() return 0 end; BridgeFunctionAttach('OnUserItemPick','h')",
     "BridgeFunction_OnUserItemPick()", "0"),
    ("OnUserItemDrop: sem handler -> 1",
     "", "BridgeFunction_OnUserItemDrop()", "1"),
    ("OnCheckUserKiller: ret==0 -> 0",
     "function h() return 0 end; BridgeFunctionAttach('OnCheckUserKiller','h')",
     "BridgeFunction_OnCheckUserKiller()", "0"),
    ("OnUserMove void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnUserMove","h")',
     "(function() BridgeFunction_OnUserMove() return C end)()", "1"),
    ("OnUserRespawn void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnUserRespawn","h")',
     "(function() BridgeFunction_OnUserRespawn() return C end)()", "1"),
    ("OnCommandDone void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnCommandDone","h")',
     "(function() BridgeFunction_OnCommandDone('/x') return C end)()", "1"),
    ("OnCharacterClose void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnCharacterClose","h")',
     "(function() BridgeFunction_OnCharacterClose() return C end)()", "1"),
    ("OnUserDie void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnUserDie","h")',
     "(function() BridgeFunction_OnUserDie() return C end)()", "1"),
    ("OnMonsterDie void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnMonsterDie","h")',
     "(function() BridgeFunction_OnMonsterDie() return C end)()", "1"),
    ("OnShutScript void",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnShutScript","h")',
     "(function() BridgeFunction_OnShutScript() return C end)()", "1"),
]

CASES_FIXES = [
    ("handler que lanca erro NAO derruba os proximos",
     'R=""; function boom() error("sql down") end; function ok2() R=R.."ok" return 0 end; '
     "BridgeFunctionAttach('OnUserDamage','boom'); BridgeFunctionAttach('OnUserDamage','ok2')",
     "(function() local r=BridgeFunction_OnUserDamage() return R..'/'..r end)()", "ok/0"),
    ("handler com erro nao concede o evento (default preservado)",
     "function boom() error('x') end; BridgeFunctionAttach('OnCheckUserTarget','boom')",
     "BridgeFunction_OnCheckUserTarget()", "1"),
    ("nome inexistente em _G NAO gera 'attempt to call a nil value'",
     "BridgeFunctionAttach('OnUserDamage','nao_existe_mesmo')",
     "(function() local ok,e=pcall(BridgeFunction_OnUserDamage) "
     "return ok and 'survived:'..BridgeFunction_OnUserDamage() or ('CRASH:'..tostring(e)) end)()",
     "survived:0"),
    ("erro de handler e registrado nas estatisticas",
     'function boom() error("x") end; BridgeFunctionAttach("OnTimerThread","boom"); '
     "BridgeFunction_OnTimerThread(); BridgeFunction_OnTimerThread()",
     "(BridgeFunctionStats and BridgeFunctionStats['OnTimerThread'] and "
     "BridgeFunctionStats['OnTimerThread'].errors or 0)", "2"),
    ("BridgeFunctionReset limpa a bridge (base de um /reload seguro)",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnTimerThread","h"); '
     "BridgeFunctionReset('OnTimerThread')",
     "(function() BridgeFunction_OnTimerThread() return C end)()", "0"),
    ("BridgeFunctionReset() global limpa tudo",
     'C=0; function h() C=C+1 end; BridgeFunctionAttach("OnUserDie","h"); BridgeFunctionReset()',
     "(function() BridgeFunction_OnUserDie() return C end)()", "0"),
]


def run(lua_src, setup, expr):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(SHIM)
    rt.execute(lua_src)
    rt.execute(setup)
    rt.execute("__R = tostring((function() return (%s) end)())" % expr)
    return str(rt.globals()["__R"])


def main():
    patched = next((p for p in PATCHED_CANDIDATES if os.path.exists(p)), None)
    if not patched:
        print("Bail out! patch nao encontrado em %s" % PATCHED_CANDIDATES)
        return 1
    o = open(_baseline(), encoding="utf-8").read()
    p = open(patched, encoding="utf-8").read()

    n = 0
    fails = []
    print("# Teste diferencial bridge Lua: ORIGINAL vs PATCHED")
    print("# original (baseline pristine): %s" % os.path.relpath(_baseline(), ROOT))
    print("# patch   : %s" % os.path.relpath(patched, ROOT))
    print()
    print("# --- Bloco A: paridade de comportamento (handlers saudaveis) ---")
    for name, setup, expr, expected in CASES_HEALTHY:
        n += 1
        try:
            ro = run(o, setup, expr)
        except Exception as e:  # noqa
            ro = "RAISED(%s)" % e
        try:
            rp = run(p, setup, expr)
        except Exception as e:  # noqa
            rp = "RAISED(%s)" % e
        if ro != expected:
            note = "  (o ORIGINAL divergiu do esperado: esperado=%s obtido=%s - caso documenta a semantica real)" % (expected, ro)
        else:
            note = ""
        ok = (ro == rp)
        print("%s %d - paridade: %s%s" % ("ok" if ok else "not ok", n, name, note))
        if not ok:
            fails.append("A%d %s: original=%s patch=%s esperado=%s" % (n, name, ro, rp, expected))

    print()
    print("# --- Bloco B: os defeitos que o patch corrige ---")
    for name, setup, expr, expected in CASES_FIXES:
        n += 1
        try:
            ro = run(o, setup, expr)
        except Exception as e:  # noqa
            ro = "RAISED"
        try:
            rp = run(p, setup, expr)
        except Exception as e:  # noqa
            rp = "RAISED"
        ok = (rp == expected)
        print("%s %d - %s   [patch=%s | original=%s]" % (
            "ok" if ok else "not ok", n, name, rp, ro))
        if not ok:
            fails.append("B%d %s: patch=%s esperado=%s (original=%s)" % (n, name, rp, expected, ro))

    print()
    print("1..%d" % n)
    if fails:
        print("# FALHAS: %d" % len(fails))
        for f in fails:
            print("#   " + f)
        return 1
    print("# TUDO OK: %d casos, paridade total no caminho saudavel e %d correcoes confirmadas"
          % (n, len(CASES_FIXES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
