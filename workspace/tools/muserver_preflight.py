#!/usr/bin/env python3
"""
muserver_preflight.py - verificacao estatica de pre-inicializacao do MuServer.

Nasceu das causas confirmadas na auditoria de 34 crash dumps:
  * handler Lua registrado por nome que nao existe em _G  -> "attempt to call a
    nil value" dentro do bridge do GameServer (P06)
  * 7/7 crashes a 0-22s de um /reload                      -> P06/P05 barram o
    estado que so aparece depois de recarregar
  * divisao inteira por zero em config lida de .dat         -> P09 sinaliza
    candidatos a divisor com valor 0
  * 4 GameServer na mesma maquina compartilhando portas     -> P02/P03
  * processo 32-bit sem LARGEADDRESSAWARE (teto de ~2GB)   -> P01
  * credenciais/seriais em texto no repositorio             -> P07 (redigido)
  * logs/dumps/lixo versionados (241 MB de .txt)            -> P08

Saida: relatorio com [ERRO]/[AVISO]/[OK] + codigo de saida (0 limpo, 1 avisos,
2 erros) para uso em CI.

Uso:
  python3 workspace/tools/muserver_preflight.py [--root MuServer] [--json out.json]
"""
import os
import re
import sys
import json
import glob
import argparse
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

SEV = {"ERROR": 2, "WARN": 1, "OK": 0}
results = []


SEVERITIES = ("ERROR", "WARN", "OK", "INFO")


def add(check, sev, msg, detail=""):
    # falhar alto aqui: uma severidade nova sem entrada no mapa de ordenacao/tag do
    # relatorio quebrava o print no FIM da execucao, depois de o JSON ja ter sido
    # escrito - e a porta de testes lia o JSON velho e dizia que estava tudo bem.
    if sev not in SEVERITIES:
        raise ValueError("severidade desconhecida %r (use %s)" % (sev, "/".join(SEVERITIES)))
    results.append({"check": check, "severity": sev, "message": msg, "detail": detail})


# --------------------------------------------------------------------------- #
# utilitarios de parsing
# --------------------------------------------------------------------------- #
def read_text(path):
    for enc in ("utf-8-sig", "utf-8", "latin-1", "utf-16"):
        try:
            with open(path, encoding=enc) as f:
                return f.read()
        except (UnicodeError, UnicodeDecodeError):
            continue
        except OSError:
            return ""
    return ""


def parse_ini(text):
    """Parseia INI tolerante a ';' e '//' como comentario. Retorna dict[(sec,key)] = valor."""
    out = {}
    sec = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("//") or line.startswith("#"):
            continue
        m = re.match(r"^\[(.+)\]\s*$", line)
        if m:
            sec = m.group(1).strip()
            continue
        m = re.match(r"^([A-Za-z0-9_\- ]+?)\s*=\s*(.*)$", line)
        if m:
            k, v = m.group(1).strip(), m.group(2).strip()
            v = re.split(r"\s*;\s*|\s*//\s*", v, 1)[0].strip()
            out[(sec, k)] = v
            out[("*", k)] = v
    return out


def _exe_base(exe_path):
    """Diretorio que a instancia usa como CWD-ancora para Data/."""
    return os.path.dirname(os.path.abspath(exe_path))


def _find_gameserver_common(root, base):
    """GameServerInfo - Common.dat pode estar em Data/, DATA/ ou um nivel acima
    (SpeedServer/ e SubSalatest/ colocam Data/ fora de GameServer/)."""
    cands = []
    for d in ("Data", "DATA", "data"):
        cands.append(os.path.join(base, d))
        cands.append(os.path.join(os.path.dirname(base), d))
    for d in cands:
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            if name.lower().startswith("gameserverinfo") and name.lower().endswith("common.dat"):
                return os.path.join(d, name)
    return None


def as_int(v):
    """Inteiro tolerante ao formato dos arquivos MU, que usam zeros a esquerda
    ('001', '00', '000').
    Cuidado que virou teste de regressao: base 0 de Python NAO aceita '002'
    (interpreta como octal e lanca ValueError), entao int(x, 0) descarta em
    silencio as linhas de dados zero-padding - e o check fica mudo. Aqui: prefixo
    0x/0o/0b usa base 0, o resto e sempre decimal."""
    if v is None:
        return None
    t = str(v).strip()
    if not t:
        return None
    try:
        if t[:2].lower() in ("0x", "0o", "0b"):
            return int(t, 0)
        return int(t, 10)
    except ValueError:
        return None


# --------------------------------------------------------------------------- #
# P01 - LARGEADDRESSAWARE / arquitetura
# --------------------------------------------------------------------------- #
def check_laa(root):
    try:
        from pe import PE, MACHINE
    except ImportError:
        add("P01", "WARN", "modulo pe.py nao encontrado - P01 pulado")
        return
    rows = []
    for p in sorted(glob.glob(os.path.join(root, "**", "*.exe"), recursive=True)):
        try:
            pe = PE(p)
        except Exception:
            continue
        if pe.machine not in (0x14C,):
            continue
        is_gs = "GameServer" in os.path.basename(p) or "GameServer" in p
        rows.append((p, pe, is_gs))
    nbad = sum(1 for _, pe, _ in rows if not pe.laa)
    gs_bad = [p for p, pe, g in rows if g and not pe.laa]
    for p, pe, g in rows:
        if g and not pe.laa:
            add("P01", "ERROR",
                "%s e PE32 sem LARGEADDRESSAWARE (imagem %.1f MB)" % (
                    os.path.relpath(p, os.path.dirname(root)), pe.sizeimg / 1048576),
                "Processo 32-bit sem LAA tem ~2 GB de espaco de endereco; com imagem de "
                "%.1f MB + heap de itens/monstres, exaustao de endereco e um modo de falha esperado. "
                "ATENCAO: o binario esta protegido (Themida) - ver P11 antes de mexer no header."
                % (pe.sizeimg / 1048576))
        elif g:
            add("P01", "OK", "%s tem LAA ativo" % os.path.relpath(p, os.path.dirname(root)))
    if not gs_bad:
        add("P01", "OK", "nenhum GameServer PE32 sem LAA")
    return {"exes_x86": len(rows), "sem_laa": nbad, "gameserver_sem_laa": gs_bad}


# --------------------------------------------------------------------------- #
# P02/P03 - portas e enderecos
# --------------------------------------------------------------------------- #
def check_ports(root):
    ports = collections.defaultdict(list)
    gs = {}
    gs_roots = sorted({_exe_base(p) for p in glob.glob(
        os.path.join(root, "**", "GameServer.exe"), recursive=True)})
    for base in gs_roots:
        dat = _find_gameserver_common(root, base)
        if not dat:
            add("P02", "WARN", "%s: GameServerInfo - Common.dat nao localizado" % os.path.relpath(base, root),
                "procurado em Data/, DATA/ e no diretorio-mae; sem este arquivo a instancia nao define portas")
            continue
        cfg = parse_ini(read_text(dat))
        name = cfg.get(("*", "ServerName"), os.path.basename(base))
        code = cfg.get(("*", "ServerCode"), "?")
        sp = as_int(cfg.get(("*", "ServerPort")))
        gs[base] = (name, code, cfg, dat)
        if sp is None:
            add("P02", "ERROR", "%s: ServerPort ausente/invalido" % os.path.relpath(dat, root))
        else:
            ports[("ServerPort", sp)].append(os.path.relpath(base, root))
    dup = {k: v for k, v in ports.items() if len(v) > 1}
    for (what, port), lst in dup.items():
        add("P02", "ERROR", "colisao de %s=%d entre %d GameServer" % (what, port, len(lst)),
            "instancias: " + ", ".join(lst) + " - binds simultaneos falham (WSAStartup/10048)")
    if not dup:
        add("P02", "OK", "nenhuma colisao de ServerPort entre as %d instancias de GameServer" % len(gs))

    cs = parse_ini(read_text(os.path.join(root, "ConnectServer", "ConnectServer.ini")))
    js = parse_ini(read_text(os.path.join(root, "JoinServer", "JoinServer.ini")))
    ds = parse_ini(read_text(os.path.join(root, "DataServer", "DataServer.ini")))
    cs_udp = as_int(cs.get(("*", "ConnectServerPortUDP")))
    js_conn = as_int(js.get(("*", "ConnectServerPort")))
    ds_port = as_int(ds.get(("*", "DataServerPort")))
    js_port = as_int(js.get(("*", "JoinServerPort")))

    def link(label, a, b, an, bn):
        if a is None or b is None:
            add("P03", "WARN", "%s: valor ausente (%s=%s, %s=%s)" % (label, an, a, bn, b))
        elif a != b:
            add("P03", "ERROR", "%s: %s=%d mas %s=%d - servicos nao vao se falar" % (label, an, a, bn, b))
        else:
            add("P03", "OK", "%s consistente (%s=%d)" % (label, an, a))

    link("JoinServer -> ConnectServer", js_conn, cs_udp, "JoinServer.ConnectServerPort",
         "ConnectServer.ConnectServerPortUDP")
    for base, (name, code, cfg, path) in gs.items():
        tag = os.path.relpath(base, root)
        link("%s: GS -> ConnectServer" % tag, as_int(cfg.get(("*", "ConnectServerPort"))), cs_udp,
             "GS.ConnectServerPort", "ConnectServer.ConnectServerPortUDP")
        link("%s: GS -> JoinServer" % tag, as_int(cfg.get(("*", "JoinServerPort"))), js_port,
             "GS.JoinServerPort", "JoinServer.JoinServerPort")
        link("%s: GS -> DataServer" % tag, as_int(cfg.get(("*", "DataServerPort"))), ds_port,
             "GS.DataServerPort", "DataServer.DataServerPort")
        sc = as_int(code)
        if sc is not None and sc in [int(c[1]) for c in gs.values() if as_int(c[1]) is not None]:
            others = [b for b, c in gs.items() if as_int(c[1]) == sc and b != base]
            if others:
                add("P02", "ERROR", "ServerCode=%s duplicado entre %s e %s" % (
                    sc, tag, ", ".join(os.path.relpath(o, root) for o in others)),
                    "JoinServer roteia por ServerCode; duplicado faz players cairem na instancia errada")
    return {"gameserver_instances": len(gs), "collisions": len(dup)}


# --------------------------------------------------------------------------- #
# P04 - MonsterSetBase
# --------------------------------------------------------------------------- #
def check_monstersets(root):
    """MonsterSetBase tem DOIS formatos no mesmo arquivo, separados por uma linha
    de secao ('0' = [NPCS] 6 colunas, '1' = [SPOTS] 8 colunas com Begin/End):
        NPCS : Monster Map Range X Y Dir Comment
        SPOTS: Monster Map Range BeginX BeginY EndX EndY Dir Quantity Comment
    Validar sem distinguir os dois gera falso positivo em massa (foi o caso de uma
    primeira versao deste check, que marcou 1113/1113 linhas). Direcao pode ser
    negativa neste pack (valores -1..-8 encontrados) e portanto NAO e validada.
    O que da para provar estaticamente e o par de coordenadas invertido e o mapa
    sem arquivo de terreno."""
    mbs = sorted(glob.glob(os.path.join(root, "Data", "MonsterSetBase", "**", "*.txt"),
                          recursive=True))
    terrmaps = set()
    for f in glob.glob(os.path.join(root, "Data", "Terrain", "*.att")):
        m = re.match(r"[Tt]errain(\d+)\.[Aa][Tt][Tt]$", os.path.basename(f))
        if m:
            terrmaps.add(int(m.group(1)))
    named = [os.path.basename(f) for f in glob.glob(os.path.join(root, "Data", "Terrain", "*.att"))]
    total = 0
    bad_rows = []
    mal_rows = []
    malformed = 0
    rows_by_map = collections.Counter()
    for f in mbs:
        rel = os.path.relpath(f, root)
        mode = None
        for ln, line in enumerate(read_text(f).splitlines(), 1):
            s = line.strip()
            if not s or s.startswith("//") or s.startswith("#") or s.startswith(";"):
                continue
            if re.match(r"^[01]\s*$", s):
                mode = int(s)
                continue
            parts = s.split()
            if len(parts) < 6 or not re.match(r"^-?\d+$", parts[0]):
                continue
            nums = [as_int(x) for x in parts[:9]]
            if any(x is None for x in nums[:2]):
                continue
            mon, mp = nums[0], nums[1]
            rng = nums[2]
            rows_by_map[mp] += 1
            total += 1
            spots = (mode == 1 and len(parts) >= 8)
            need = 7 if spots else 5
            if any(x is None for x in nums[2:need]):
                # coluna obrigatoria nao numerica: dado malformado de verdade
                malformed += 1
                if len(mal_rows) < 10:
                    mal_rows.append("%s:%d -> %r" % (rel, ln, s[:88]))
                continue
            if spots:
                bx, by, ex, ey = nums[3], nums[4], nums[5], nums[6]
                if not all(0 <= v <= 255 for v in (bx, by, ex, ey)):
                    bad_rows.append("%s:%d monster=%d map=%d faixa (%d,%d)-(%d,%d) fora de 0..255"
                                    % (rel, ln, mon, mp, bx, by, ex, ey))
                elif ex < bx or ey < by:
                    bad_rows.append("%s:%d monster=%d map=%d faixa invertida Begin(%d,%d) > End(%d,%d)"
                                    % (rel, ln, mon, mp, bx, by, ex, ey))
                elif rng is not None and rng < 0:
                    bad_rows.append("%s:%d monster=%d map=%d Range negativo (%d)"
                                    % (rel, ln, mon, mp, rng))
            else:
                x, y = nums[3], nums[4]
                if not all(0 <= v <= 255 for v in (x, y)):
                    bad_rows.append("%s:%d monster=%d map=%d (%d,%d) fora de 0..255"
                                    % (rel, ln, mon, mp, x, y))
                elif rng is not None and rng < 0:
                    bad_rows.append("%s:%d monster=%d map=%d Range negativo (%d)"
                                    % (rel, ln, mon, mp, rng))
    if mal_rows:
        add("P04", "WARN", "%d linha(s) de spawn com menos colunas do que a secao exige"
            % malformed,
            "linhas de 6 colunas (formato NPCS) dentro de uma secao [SPOTS] de 8 colunas: o servidor "
            "le EndX/EndY como ausentes. Consequencia exata (ignorar ou parsear errado) depende do "
            "parser do GameServer, que e protegido - por isso AVISO e nao ERRO. Amostras:\n      "
            + "\n      ".join(mal_rows))
    if bad_rows:
        add("P04", "ERROR", "%d linha(s) de spawn com geometria invalida em %d linhas validadas"
            % (len(bad_rows), total), "\n      ".join(bad_rows[:10]))
    else:
        add("P04", "OK", "%d linhas de spawn validadas (formato NPCS/SPOTS distinguido, "
            "coordenadas em 0..255, faixa Begin<=End)" % total)

    orphan_maps = sorted(m for m in rows_by_map if m not in terrmaps and rows_by_map[m] > 0)
    if orphan_maps:
        n = sum(rows_by_map[m] for m in orphan_maps)
        add("P04", "WARN",
            "%d mapa(s) com %d linha(s) de spawn sem Terrain<map>.att no pack" % (len(orphan_maps), n),
            "mapas: " + ", ".join("%d(%d)" % (m, rows_by_map[m]) for m in orphan_maps[:16]) +
            "\n      terreno numerado disponivel: %d arquivos; nomes alternativos existem (%s) - "
            "confirmar contra a deploy de referencia antes de remover spawns. Correlacao com os logs: "
            "2 dos 3 mapas mais rejeitados (24, 27) estao nesta lista." % (
                len(terrmaps), ", ".join(x for x in named if not x.lower().startswith("terrain"))[:60]))
    logs = glob.glob(os.path.join(root, "**", "LOG", "*.txt"), recursive=True)
    hits = 0
    days = set()
    for lg in logs:
        t = read_text(lg)
        if "Incorrect Monster Position" in t:
            hits += t.count("Incorrect Monster Position")
            days.add(os.path.basename(lg))
    if hits:
        add("P04", "WARN", "logs: %d ocorrencias de 'Incorrect Monster Position' em %d dia(s) de log"
            % (hits, len(days)),
            "defeito cronico de dados. NAO provado como causa dos crashes (aparece em quase todos os "
            "dias, inclusive sem crash); a calibracao contra o terreno refutou a hipotese de tile "
            "intransitavel para os mapas que tem terreno - ver workspace/reports/terrain.json")
    return {"lines": total, "bad_geometry": len(bad_rows), "malformed": malformed,
            "maps_without_terrain": len(orphan_maps)}


# --------------------------------------------------------------------------- #
# P05/P06 - Lua
# --------------------------------------------------------------------------- #
def check_lua(root):
    trees = []
    for d in ("Data", "DATA"):
        trees += [t for t in glob.glob(os.path.join(root, "**", d, "Script"), recursive=True)
                  if os.path.isdir(t)]
    trees = sorted(set(trees)) or [os.path.join(root, "Data", "Script")]
    lua_files = sorted({f for t in trees for f in glob.glob(os.path.join(t, "**", "*.lua"), recursive=True)})
    add("P05", "OK", "%d arvore(s) Data/Script, %d arquivos .lua" % (len(trees), len(lua_files)))
    if not lua_files:
        add("P05", "WARN", "nenhum .lua em Data/Script")
        return {}
    defined = {}
    attached = []
    for f in lua_files:
        txt = read_text(f)
        rel = os.path.relpath(f, root)
        for m in re.finditer(r"^\s*(?:local\s+)?function\s+([A-Za-z_][\w:.]*)\s*\(", txt, re.M):
            defined.setdefault(m.group(1).split(".")[-1], rel)
        for m in re.finditer(r"^\s*(?:local\s+)?([A-Za-z_][\w]*)\s*=\s*function", txt, re.M):
            defined.setdefault(m.group(1), rel)
        for m in re.finditer(r"BridgeFunctionAttach\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]", txt):
            attached.append((m.group(1), m.group(2), rel))
        for m in re.finditer(r"require\s*\(\s*['\"]([^'\"]+)['\"]", txt):
            mod = m.group(1).replace("\\", os.sep).replace("/", os.sep)
            base = os.path.dirname(f)
            cands = [os.path.join(base, mod + ".lua"),
                     os.path.join(root, "Data", "Script", mod + ".lua")]
            hit = any(os.path.exists(c) for c in cands)
            exact = any(os.path.exists(c) and os.path.basename(c) == os.path.basename(mod) + ".lua"
                        and _case_ok(c) for c in cands)
            if not hit:
                add("P05", "ERROR", "%s: require('%s') nao resolve em nenhum arquivo" % (rel, m.group(1)))
            elif not exact:
                add("P05", "WARN", "%s: require('%s') so casa por casualidade de case-insensitive (Windows)"
                    % (rel, m.group(1)),
                    "o arquivo real e um dos candidatos com caixa diferente; em FS case-sensitive "
                    "ou num loader que compare nomes exatos isso quebra")
    # sintaxe
    try:
        sys.path.insert(0, "/home/user/.venv-tools/lib/python3.11/site-packages")
        from luaparser import ast as lust
    except ImportError:
        lust = None
        add("P05", "WARN", "luaparser ausente - validacao de sintaxe pulada")
    nsyn = 0
    if lust:
        for f in lua_files:
            head = open(f, "rb").read(8)
            if head[:4] not in (b"\x1bLua", b"--[[", b"local ", b"func", b"Brid", b"LogC") and \
                    not _looks_text(open(f, "rb").read(256)):
                continue
            try:
                lust.parse(read_text(f))
            except Exception as e:
                nsyn += 1
                add("P05", "ERROR", "%s: Lua invalido - %s" % (os.path.relpath(f, root), str(e)[:120]))
        if not nsyn:
            add("P05", "OK", "sintaxe Lua valida em %d arquivos" % len(lua_files))
    # handlers anexados sem definicao -> fonte direta do crash por nil-call
    orphan = [(b, fn, f) for b, fn, f in attached if fn not in defined]
    if orphan:
        add("P06", "ERROR", "%d handler(s) anexados a bridge sem definicao correspondente" % len(orphan),
            "\n      ".join("%s -> _G['%s']  (%s)" % t for t in orphan[:15]) +
            "\n      efeito: o ScriptCore original faz _G[nome]() sem guarda -> 'attempt to call a nil "
            "value' dentro do bridge; com o ScriptCore corrigido isso vira log, nao crash")
    else:
        add("P06", "OK", "todos os %d handlers anexados tem definicao estatica" % len(attached))
    bridges = {b for b, _, _ in attached}
    core = os.path.join(root, "Data", "Script", "System", "ScriptCore.lua")
    if os.path.exists(core):
        decl = set(re.findall(r"function\s+BridgeFunction_([A-Za-z]+)\s*\(", read_text(core)))
        dead = sorted(decl - bridges)
        if dead:
            add("P06", "WARN", "%d bridge(s) implementada(s) mas sem nenhum script anexado" % len(dead),
                "ganchos implementados no ScriptCore para os quais nenhum script anexou handler: "
            + ", ".join(dead))
    decl_all = set()
    if os.path.exists(core):
        decl_all = set(re.findall(r"function\s+BridgeFunction_([A-Za-z]+)\s*\(", read_text(core)))
    return {"lua_files": len(lua_files), "attached": len(attached), "defined": len(defined),
            "orphan": len(orphan), "syntax_errors": nsyn,
            "dead_bridges": sorted(decl_all - bridges)}


def _case_ok(path):
    d, b = os.path.split(path)
    if not os.path.isdir(d):
        return False
    return b in os.listdir(d)


def _looks_text(b):
    try:
        b.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


# --------------------------------------------------------------------------- #
# P07 - segredos (sempre redigidos)
# --------------------------------------------------------------------------- #
SECRET_PATTERNS = [
    ("senha global em texto", re.compile(r"^\s*GlobalPassword\s*=\s*(\S+)", re.M | re.I)),
    ("token de bot do Discord", re.compile(r"^\s*DiscordBotToken\s*=\s*(\S+)", re.M | re.I)),
    ("serial de cliente", re.compile(r"^\s*(?:ClientSerial|ServerSerial)\s*=\s*(\S+)", re.M | re.I)),
    ("hardware id de licenca", re.compile(r"^\s*CustomerHardwareId\s*=\s*(\S+)", re.M | re.I)),
    ("senha no connection string", re.compile(r"(?:Pwd|Password|UID)\s*=\s*([^;\s'\"]+)", re.I)),
    ("string de conexao ODBC com credencial", re.compile(r"Dsn=[^;\s]*;Uid=[^;\s]*;Pwd=[^;\s]*", re.I)),
]


def redact(v):
    v = str(v)
    if len(v) <= 4:
        return "*" * len(v)
    return v[:2] + "*" * (len(v) - 4) + v[-2:]


def check_secrets(root):
    hits = collections.Counter()
    files = collections.defaultdict(list)
    exts = ("*.ini", "*.dat", "*.txt", "*.lua", "*.sql", "*.reg", "*.xml", "*.json", "*.config")
    for pat in exts:
        for f in glob.glob(os.path.join(root, "**", pat), recursive=True):
            if os.path.getsize(f) > 2 * 1024 * 1024:
                continue
            txt = read_text(f)
            if not txt:
                continue
            for label, rx in SECRET_PATTERNS:
                for m in rx.finditer(txt):
                    hits[label] += 1
                    files[label].append(os.path.relpath(f, root))
    for label, n in hits.items():
        uniq = sorted(set(files[label]))
        add("P07", "ERROR", "%s: %d ocorrencia(s) em %d arquivo(s)" % (label, n, len(uniq)),
            "valores REDIGIDOS; arquivos: " + ", ".join(uniq[:6]) +
            ("" if len(uniq) <= 6 else " (+%d)" % (len(uniq) - 6)))
    if not hits:
        add("P07", "OK", "nenhum padrao de credencial em texto nos arquivos de configuracao")
    # backups de banco com dados de jogadores. *.bak NAO implica "banco": neste
    # pack 4 dos 5 sao dumps do SQL Server (contem PII) e o 5o e um .xml.bak de
    # configuracao do StartUp. Classificar pela extensao denunciria um incidente de
    # dados onde so ha um backup de config comum - por isso a assinatura.
    baks = [b for b in glob.glob(os.path.join(root, "**", "*.bak"), recursive=True)
            if _looks_like_mssql_backup(b)]
    others = [b for b in glob.glob(os.path.join(root, "**", "*.bak"), recursive=True)
              if b not in baks]
    if baks:
        tot = sum(os.path.getsize(b) for b in baks)
        add("P07", "ERROR", "%d backup(s) de banco versionados (%s bytes) contendo dados de jogadores"
            % (len(baks), "{:,}".format(tot)),
            ", ".join(os.path.relpath(b, root) for b in baks[:5]) +
            " - assinatura de backup do SQL Server; hashes de senha e PII; remover "
            "do VCS e tratar como incidente de divulgacao")
    if others:
        add("P07", "INFO", "%d arquivo(s) .bak que NAO sao backup de banco" % len(others),
            ", ".join(os.path.relpath(b, root) for b in others[:5]) +
            " - backup de config; higiene de repositorio (P08), nao incidente de dados")
    return {"secret_hits": sum(hits.values()), "bak_files": len(baks)}


# --------------------------------------------------------------------------- #
# P08 - higiene de repositorio
# --------------------------------------------------------------------------- #
def _looks_like_mssql_backup(path):
    """Assinatura de backup do SQL Server: o media header comeca com os 4 bytes
    ASCII 'TAPE' no offset 0 (confirmado nos 4 arquivos de MuServer/DB).
    Procurar texto tipo 'Microsoft SQL Server' em qualquer lugar dos primeiros
    512 bytes deu FALSO POSITIVO aqui: bor_StartUp.xml.bak e texto XML com BOM
    que menciona o servidor SQL. assinatura em offset fixo e a unica forma de
    distinguir 'dump de banco com PII' de 'backup de config'. Byte nulo logo
    depois do cabecalho tambem caracteriza a midia binaria."""
    try:
        with open(path, "rb") as f:
            head = f.read(64)
    except OSError:
        return False
    if head[:4] == b"TAPE" and b"\x00" in head[4:16]:
        return True
    # fita 'DISK' em vez de 'TAPE' (backup em arquivo .bak em disco e o caso comum)
    return head[:2] == b"\x01\x00" and b"TAPE" in head[16:64]


def _tracked_files(root):
    """Arquivos que o Git REALMENTE guarda, via git ls-files. P08 fala de ruido de
    repositorio: medir o disco (glob) contaria lixo ja ignorado e daria um numero
    que o dono nao consegue reproduzir com git. Sem git, cai para o disco e diz."""
    try:
        import subprocess
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                             capture_output=True, timeout=120)
        if out.returncode == 0:
            rel = [p.decode("utf-8", "replace") for p in out.stdout.split(b"\0") if p]
            return set(os.path.normpath(os.path.join(root, p)) for p in rel), True
    except Exception:  # noqa: BLE001 - sem git/timeout: melhor medir o disco e avisar
        pass
    return None, False


def check_hygiene(root):
    tracked, used_git = _tracked_files(root)
    cats = {
        "log": ("*.txt", re.compile(r"[\\/]LOG[\\/]", re.I)),
        "crash dump": ("*.dmp", None),
        "temporario de editor": ("*.tmp", None),
        "backup (.bak)": ("*.bak", None),
        "midia empacotada (.ozt/.ozj)": ("*.ozt", None),
    }
    summary = {}
    for name, (pat, filt) in cats.items():
        if pat is None:
            continue
        fl = glob.glob(os.path.join(root, "**", pat), recursive=True)
        if filt:
            fl = [f for f in fl if filt.search(f)]
        if tracked is not None:
            fl = [f for f in fl if os.path.normpath(f) in tracked]
        sz = sum(os.path.getsize(f) for f in fl)
        summary[name] = (len(fl), sz)
    t = sum(v[0] for v in summary.values())
    b = sum(v[1] for v in summary.values())
    base = ("contados do indice do git (git ls-files)" if used_git
            else "contados do disco; git indisponivel")
    add("P08", "WARN", "%d arquivos de artefatos nao-fonte versionados (%s bytes) - %s" % (
        t, "{:,}".format(b), base),
        "  ".join("%s=%d (%s)" % (k, v[0], "{:,}".format(v[1])) for k, v in summary.items() if v[0]) +
        " - candidato a .gitignore + git-filter-repo para tirar do historico")
    dup = collections.defaultdict(int)
    for f in glob.glob(os.path.join(root, "**", "*.tmp"), recursive=True):
        dup[os.path.dirname(f)] += 1
    for d, n in sorted(dup.items(), key=lambda kv: -kv[1])[:4]:
        if n > 20:
            add("P08", "WARN", "%d arquivos .tmp acumulado(s) em %s" % (n, os.path.relpath(d, root)),
                "lixo de sessao do editor de Lua; ver workspace/tools/recover_tmp_lua.py "
                "ANTES de apagar - e a unica copia legivel de um script")
    return summary


# --------------------------------------------------------------------------- #
# P09 - candidatos a divisor com valor zero
# --------------------------------------------------------------------------- #
RISKY = re.compile(r"(Max|Count|Total|Rate|Divis|Per|Step|Slot|Level|Size|Amount|Num)\w*$", re.I)


def _family(k):
    """Agrupa chaves pelo nome sem os indices de sufixo (..._AL1, Rate2, [3])."""
    base = re.sub(r"([0-9]+)\s*$", "", k)
    base = re.sub(r"([A-Za-z]{1,3})([0-9]+)\s*$", r"\1#", base)
    return base.strip()


def check_zero_divisors(root):
    """Sinal agudo: um membro ZERO numa familia de configs onde os irmaos sao
    nao-zero. E o padrao dos 6 INTEGER_DIVIDE_BY_ZERO dos dumps: o divisor e um
    elemento de VETOR de config (movzx eax,[obj+0xa8]; mov ecx,[eax*4+global]),
    entao um unico furo no vetor produz divisao por zero para um subconjunto de
    itens/niveis e nao para todos - exatamente o comportamento intermitente visto.
    Uma lista de "todas as chaves = 0" teria centenas de itens inofensivos."""
    fams = collections.defaultdict(dict)
    for f in sorted(glob.glob(os.path.join(root, "**", "GameServerInfo - *.dat"), recursive=True)):
        cfg = parse_ini(read_text(f))
        for (sec, k), v in cfg.items():
            if sec == "*":
                continue
            iv = as_int(v)
            if iv is None:
                continue
            fams[_family(k)][k] = iv
    holes = []
    total_zero = 0
    for fam, kv in fams.items():
        if len(kv) < 2:
            continue
        zeros = [k for k, v in kv.items() if v == 0]
        nonzero = [v for v in kv.values() if v != 0]
        total_zero += len(zeros)
        if zeros and nonzero and len(nonzero) >= max(1, len(kv) // 2):
            holes.append((fam, sorted(zeros), sorted(nonzero)[:4], len(kv)))
    if holes:
        add("P09", "WARN", "%d familia(s) de config com membro ZERO entre irmaos nao-zero" % len(holes),
            "evidencia: 6 crashes INTEGER_DIVIDE_BY_ZERO, todos `idiv dword ptr [global]` onde o global "
            "e um elemento de vetor de config. Familia mais afetada: %s (zeros: %s; irmaos: %s). "
            "Revistos manualmente antes de qualquer alteracao - correlacao, nao causalidade provada." % (
                holes[0][0], ", ".join(holes[0][1][:4]), ", ".join(map(str, holes[0][2]))))
        for fam, z, nz, n in sorted(holes, key=lambda x: -len(x[1]))[:6]:
            add("P09", "WARN", "  familia %s: %d/%d membros = 0" % (fam, len(z), n),
                "zeros: " + ", ".join(z[:6]) + "   |   nao-zero: " + ", ".join(map(str, nz)))
    else:
        add("P09", "OK", "nenhuma familia de config com furo (membro 0 entre irmaos != 0)")
    return {"families_with_hole": len(holes), "zero_keys_total": total_zero}


# --------------------------------------------------------------------------- #
# P10 - divergencia de dados entre instancias
# --------------------------------------------------------------------------- #
def check_data_drift(root):
    bases = sorted({os.path.dirname(os.path.dirname(p))
                    for p in glob.glob(os.path.join(root, "**", "GameServer.exe"), recursive=True)})
    if len(bases) < 2:
        return {}
    prim = os.path.join(root, "Data")
    report = []
    for b in bases:
        d = os.path.join(b, "Data")
        if not os.path.isdir(d) or os.path.abspath(d) == os.path.abspath(prim):
            continue
        same = diff = only = 0
        difflist = []
        for f in glob.glob(os.path.join(d, "**", "*.*"), recursive=True):
            rel = os.path.relpath(f, d)
            g = os.path.join(prim, rel)
            if not os.path.exists(g):
                only += 1
                continue
            if os.path.getsize(f) != os.path.getsize(g):
                diff += 1
                difflist.append(rel)
                continue
            with open(f, "rb") as fh1, open(g, "rb") as fh2:
                if fh1.read() != fh2.read():
                    diff += 1
                    difflist.append(rel)
                else:
                    same += 1
        report.append((os.path.relpath(d, root), same, diff, only, difflist[:8]))
        if diff:
            add("P10", "WARN", "%s difere de MuServer/Data em %d arquivo(s) de %d" % (
                os.path.relpath(d, root), diff, same + diff + only),
                "arquivos que diferem de MuServer/Data - pode ser INTENCIONAL (instancia "
                "secundaria/de teste), mas e a principal fonte de comportamento inesperado. "
                "Revistos: " + ", ".join(difflist[:8]))
    return {"compared": len(report), "report": report}


# --------------------------------------------------------------------------- #
# P11 - protetores / viabilidade de modificacao
# --------------------------------------------------------------------------- #
def check_protectors(root):
    try:
        from pe import PE
    except ImportError:
        return {}
    prot = []
    for p in sorted(glob.glob(os.path.join(root, "**", "*.exe"), recursive=True)):
        try:
            pe = PE(p)
        except Exception:
            continue
        names = {s["name"] for s in pe.secs}
        hit = names & {".themida", ".vmp0", ".vmp1", ".enigma1", ".enigma2", ".boot", ".pentry"}
        if hit:
            prot.append((os.path.relpath(p, root), sorted(hit)))
    for p, h in prot:
        add("P11", "ERROR", "%s protegido por %s" % (p, ",".join(h)),
            "codigo-fonte indisponivel e binario empacotado: NAO recompilavel, NAO patcheavel com "
            "seguranca (Themida pode validar o proprio header). Diagnosticos possiveis: memoria de "
            "dump, logs, e camada Lua/dados. NAO tentarei neutralizar a protecao de licenca.")
    if not prot:
        add("P11", "OK", "nenhum protetor detectado")
    return {"protected": len(prot)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/home/user/Muserver/MuServer")
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    if not os.path.isdir(root):
        print("raiz nao encontrada:", root)
        return 2

    checks = [
        ("P01 LARGEADDRESSAWARE / arquitetura", lambda: check_laa(root)),
        ("P02/P03 portas e interconexao", lambda: check_ports(root)),
        ("P04 MonsterSetBase", lambda: check_monstersets(root)),
        ("P05/P06 camada Lua", lambda: check_lua(root)),
        ("P07 segredos e PII", lambda: check_secrets(root)),
        ("P08 higiene de repositorio", lambda: check_hygiene(root)),
        ("P09 divisores zerados", lambda: check_zero_divisors(root)),
        ("P10 drift de dados entre instancias", lambda: check_data_drift(root)),
        ("P11 protetores de binario", lambda: check_protectors(root)),
    ]
    summary = {}
    for label, fn in checks:
        print("### %s" % label, file=sys.stderr)
        try:
            summary[label] = fn() or {}
        except Exception as e:  # noqa
            add(label.split()[0], "WARN", "check lancou excecao: %s: %s" % (type(e).__name__, e))

    errs = [r for r in results if r["severity"] == "ERROR"]
    warns = [r for r in results if r["severity"] == "WARN"]
    oks = [r for r in results if r["severity"] == "OK"]
    infos = [r for r in results if r["severity"] == "INFO"]
    order = {"ERROR": 0, "WARN": 1, "OK": 2, "INFO": 3}
    tags = {"ERROR": "[ERRO ]", "WARN": "[AVISO]", "OK": "[ OK  ]", "INFO": "[ INFO ]"}

    # JSON ANTES do relatorio em stdout. Na ordem antiga, uma excecao no print
    # (faltava 'INFO' no mapa de tag) deixava o JSON da execucao anterior no
    # disco, e a porta de testes - que so confere o JSON - lia o arquivo velho e
    # reportava verde para uma ferramenta quebrada. Daqui pra frente o JSON e a
    # fonte de verdade e o print e so apresentacao.
    if a.json:
        import datetime
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump({"summary": summary,
                       "run_stamp": datetime.datetime.now(datetime.timezone.utc)
                                        .strftime("%Y-%m-%dT%H:%M:%SZ"),
                       "root": os.path.abspath(root),
                       "counts": {"error": len(errs), "warn": len(warns),
                                  "ok": len(oks), "info": len(infos)},
                       "results": results},
                      f, indent=1, ensure_ascii=False)

    print("=" * 96)
    print("PREFLIGHT MuServer  |  %s" % root)
    print("=" * 96)
    for r in sorted(results, key=lambda x: (order[x["severity"]], x["check"])):
        print("%s %-6s %s" % (tags[r["severity"]], r["check"], r["message"]))
        if r["detail"]:
            for line in str(r["detail"]).splitlines():
                print("         %s" % line)
    print("-" * 96)
    extra = (", %d info" % len(infos)) if infos else ""
    print("resumo: %d erro(s), %d aviso(s), %d ok%s" % (len(errs), len(warns), len(oks), extra))
    if a.json:
        print("json: %s" % a.json)
    return 2 if errs else (1 if warns else 0)


if __name__ == "__main__":
    sys.exit(main())
