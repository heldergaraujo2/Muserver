#!/usr/bin/env python3
"""lua_probe.py — Etapa F: inventario e evidencia da camada Lua e do despacho de pacotes.

Somente leitura sobre MU_REF_DATA. Medicoes, nao interpretacoes: onde o probe diz "assinatura",
diz o que casou; onde nao ha evidencia, a linha diz `desconhecido`.

Por que este probe existe: a conclusao publicada na R-6 ("0 declaracoes de framing em .lua") veio de
uma busca com tokens estreitos demais (HEAD_SIZE/PacketSize/opcode). Ela esta ERRADA e este probe e
a correcao reproduzivel: ha 20 .lua com termos de pacote e um ProtocolCore.lua real em 3 arvores de
servidor e 5 do lado cliente. Ver reports/rf-lua-protocolo.md.

Distincao obrigatoria: MuServer/Data/Script/System/ProtocolCore.lua foi MODIFICADO por trabalho
anterior desta branch (baseline em workspace/changes/originals/, md5 em ORIGINALS.md5). A evidencia
sobre o ORIGINAL vem de workspace/changes/originals/ e das copias nao tocadas (SpeedServer,
SubSalatest) — nunca do arquivo patcheado.

uso: lua_probe.py [--ref CAMINHO] [--saida TSV]
"""
import argparse
import hashlib
import os
import pathlib
import re
import shutil
import sys

TERMOS = re.compile(r"packetsize|head_size|makepacket|sendpacket|recvpacket|protocolcore|"
                    r"clearpacket", re.I)
ASSIN_SERVER = "function GameServerProtocolRecv(aIndex, Packet, PacketName)"
ASSIN_CLIENT = "function ClientProtocolRecv(Packet, PacketName)"


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for bloco in iter(lambda: f.read(1 << 16), b""):
            h.update(bloco)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default=os.environ.get("MU_REF_DATA", "../MuServer"))
    a = ap.parse_args()
    ref = pathlib.Path(a.ref)
    if not ref.is_dir():
        sys.stderr.write("lua_probe: MU_REF_DATA nao encontrado (%s)\n" % ref)
        return 2

    linhas = []

    def add(chave, valor, obs=""):
        linhas.append((chave, str(valor), obs))

    luas = sorted(p for p in ref.rglob("*.lua"))
    add("lua_total", len(luas))
    if luas:
        maior = max(luas, key=lambda p: p.stat().st_size)
        add("lua_maior_bytes", maior.stat().st_size, str(maior.relative_to(ref)))
        try:
            add("lua_maior_linhas", sum(1 for _ in open(maior, "rb")))
        except OSError:
            add("lua_maior_linhas", "desconhecido")

    com_termo = [p for p in luas if TERMOS.search(p.read_text(errors="replace"))]
    add("lua_com_termos_de_pacote", len(com_termo))
    add("lua_com_sendpacket",
        sum(1 for p in luas if "SendPacket" in p.read_text(errors="replace")))

    # ProtocolCore: servidor x cliente, e qual copia esta patcheada
    pcs = sorted(p for p in ref.rglob("ProtocolCore.lua"))
    add("protocolcore_copias", len(pcs))
    for p in pcs:
        lado = "cliente" if "Gerador de Main" in str(p) else "servidor"
        add("protocolcore", md5(p), "%s | %s" % (lado, p.relative_to(ref)))

    # Assinatura real do ponto de entrada, lida de copia NAO patcheada e do baseline
    def achaassinatura(caminhos, alvo):
        for c in caminhos:
            if not c.exists():
                continue
            for i, ln in enumerate(c.open(errors="replace"), 1):
                if alvo in ln:
                    return "%s:%d" % (c.name, i)
        return "nao_encontrada"

    raiz = pathlib.Path(__file__).resolve().parent.parent.parent   # raiz do repositorio
    orig_base = raiz / "workspace/changes/originals/ProtocolCore.lua"
    copias_servidor = [p for p in pcs if "Gerador de Main" not in str(p)]
    add("assinatura_servidor_original", achaassinatura(
        ([orig_base] if orig_base.exists() else []) + copias_servidor, ASSIN_SERVER),
        "GameServerProtocolRecv(aIndex, Packet, PacketName)")
    add("assinatura_cliente", achaassinatura(pcs, ASSIN_CLIENT),
        "ClientProtocolRecv(Packet, PacketName)")
    add("clearpacket_presente",
        sum(1 for p in pcs if "ClearPacket(" in p.read_text(errors="replace")))
    add("packetname_formatado_como_string",
        sum(1 for p in pcs if "Name: %s" in p.read_text(errors="replace")))
    add("head_formatado_como_numero",
        sum(1 for p in pcs if "Head: %d" in p.read_text(errors="replace")))

    # ferramenta de cifragem de script do cliente
    enc = ref / "Tools/Gerador de Main/LuaEncTool"
    add("luaenctool_presente", 1 if enc.is_dir() else 0)
    if enc.is_dir():
        add("luaenctool_exe", 1 if (enc / "LuaEncryptorTool.exe").exists() else 0)
        add("luaenctool_pdb", 1 if (enc / "LuaEncryptorTool.pdb").exists() else 0)
        ce = enc / "ClientEncrypted/System/ProtocolCore.lua"
        cd = enc / "ClientDecrypted/System/ProtocolCore.lua"
        if ce.exists():
            with open(ce, "rb") as f:
                add("clientencrypted_primeiros8", f.read(8).hex())
        if cd.exists():
            add("clientdecrypted_legivel",
                1 if ASSIN_CLIENT in cd.read_text(errors="replace") else 0)

    # interpretador: sem ele nao ha verificacao de sintaxe (registrado, nao omitido)
    add("interpretador_lua",
        next((b for b in ("lua", "lua5.1", "lua5.3", "lua5.4", "luajit")
              if shutil.which(b)), "ausente"))
    add("cliente_main_exe",
        sum(1 for p in ref.rglob("main.exe")),
        "saida do Gerador de Main; NAO executado")

    print("chave\tvalor\tobs")
    for c, v, o in linhas:
        print("%s\t%s\t%s" % (c, v, o))
    return 0


if __name__ == "__main__":
    sys.exit(main())
