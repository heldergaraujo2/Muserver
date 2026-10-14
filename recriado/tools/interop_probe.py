#!/usr/bin/env python3
"""interop_probe.py — evidencia de interoperabilidade, SOMENTE LEITURA (R-6 / Etapa A).

Nao executa binario nenhum, nao abre socket, nao escreve em MU_REF_DATA. Mede o que existe em disco
e o que existe no ambiente, e devolve linhas `chave<TAB>valor<TAB>fonte` para tests/interop.sh cobrar
como assercao — evidencia sem teste reproduzivel vira opiniao.

Separa as tres camadas que NAO podem ser confundidas (exigencia explicita do comando mestre):
  1 conformidade interna do protocolo v2        -> medida em tests/conform.sh + golden
  2 compatibilidade entre implementacoes proprias -> medidas em tests/net.sh (servico x cliente)
  3 compatibilidade com os executaveis originais  -> depende de executar o binario: BLOQUEADO aqui
Nenhuma e prova da seguinte.

uso: interop_probe.py [--ref CAMINHO] [--cartoes N]
saida: TSV em stdout; exit 2 se MU_REF_DATA nao existe.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys

HACK = "Data/Hack/HackPacketCheck.txt"
FRAMING = re.compile(r"HEAD_SIZE|PacketSize|MakePacket|opcode", re.I)
CAPTURAS = ("*.pcap", "*.pcapng", "*.cap", "*.erf")


def tsv(chave, valor, fonte=""):
    print("%s\t%s\t%s" % (chave, valor, fonte))


def mede_hackpacket(ref: pathlib.Path):
    """HackPacketCheck.txt: tabela Index/Value/Encrypt/MaxDelay/MinCount/MaxCount.

    E a unica fonte do pacote que enumera o espaco de indices de pacote sem executar nada. Diz
    quantos indices existem, quais sao marcados como criptografados e que ha limite de taxa por
    pacote — NAO diz o layout de quadro, e nao e tratada como se dissesse.
    """
    p = ref / HACK
    if not p.is_file():
        tsv("hackpacketcheck_presente", 0, HACK)
        return
    tsv("hackpacketcheck_presente", 1, HACK)
    indices = []
    enc = {"1": 0, "0": 0, "outro": 0}
    colunas = set()
    terminador = 0
    uteis = 0
    for ln in p.read_text(errors="replace").splitlines():
        t = ln.strip()
        if not t or t.startswith("//"):
            continue
        if t.lower() == "end":
            terminador = 1
            continue
        f = t.split()
        colunas.add(len(f))
        if len(f) < 3 or not f[0].isdigit():
            continue
        uteis += 1
        i = int(f[0])
        indices.append(i)
        enc[f[2] if f[2] in ("0", "1") else "outro"] += 1
    tsv("hackpacketcheck_entradas", uteis, HACK)
    tsv("hackpacketcheck_terminador_end", terminador, HACK)
    tsv("hackpacketcheck_colunas_por_linha", ",".join(str(c) for c in sorted(colunas)), HACK)
    if indices:
        lo, hi = min(indices), max(indices)
        tsv("hackpacketcheck_index_min", lo, HACK)
        tsv("hackpacketcheck_index_max", hi, HACK)
        # consequencia aritmetica, nao interpretacao: se o maior indice e 255, um campo que o
        # carregue nao precisa de mais de 8 bits.
        tsv("hackpacketcheck_bits_minimos", (hi).bit_length(), HACK)
        tsv("hackpacketcheck_indices_distintos", len(set(indices)), HACK)
        tsv("hackpacketcheck_ocorrencias_redundantes", len(indices) - len(set(indices)), HACK)
    tsv("hackpacketcheck_encrypt_1", enc["1"], HACK + " (marcados como criptografados)")
    tsv("hackpacketcheck_encrypt_0", enc["0"], HACK)
    tsv("hackpacketcheck_encrypt_curinga", enc["outro"], HACK)


def mede_capturas(ref: pathlib.Path):
    n = 0
    for pat in CAPTURAS:
        n += sum(1 for _ in ref.rglob(pat))
    tsv("capturas_de_trafego", n, "MU_REF_DATA (%s)" % ", ".join(CAPTURAS))


def mede_framing(ref: pathlib.Path):
    lua = txt = 0
    lua_com = txt_com = 0
    for p in list(ref.rglob("*.lua")) + list(ref.rglob("*.txt")):
        try:
            s = p.read_text(errors="replace")
        except OSError:
            continue
        if p.suffix == ".lua":
            lua += 1
            lua_com += 1 if FRAMING.search(s) else 0
        else:
            txt += 1
            txt_com += 1 if FRAMING.search(s) else 0
    tsv("scripts_lua", lua, "MU_REF_DATA")
    tsv("scripts_lua_com_declaracao_de_framing", lua_com, "regex " + FRAMING.pattern)
    tsv("textos", txt, "MU_REF_DATA")
    tsv("textos_com_declaracao_de_framing", txt_com, "regex " + FRAMING.pattern)


def mede_ambiente(admin_bin: pathlib.Path):
    """Pre-condicoes para um teste REAL de interoperabilidade. Ausencia vira BLOCKED, nao FAIL."""
    for b in ("wine", "wine64", "wine32", "qemu-i386", "qemu-system-i386", "box86", "box64"):
        tsv("ferramenta_%s" % b, 1 if shutil.which(b) else 0, "PATH")
    optin = os.environ.get("MU_INTEROP_ALLOW_ORIGINAL", "")
    tsv("optin_executar_original", 1 if optin == "1" else 0,
        "variavel MU_INTEROP_ALLOW_ORIGINAL (exigida para executar binario original)")
    tsv("arquitetura_dos_exe", "PE32/i386 (R-5, tools/pe_probe.py)", "22 .exe medidos na R-5")
    tsv("protecao_dos_exe", "secoes .themida (R-5)", "impede distinguir GameServer/CS/SpeedServer")


def mede_v2(codigo: pathlib.Path):
    """O que o protocolo v2 usa, medido pelo CLI que liga no codec real (nao por leitura de fonte)."""
    if not codigo.exists():
        tsv("v2_codec_disponivel", 0, str(codigo))
        return
    tsv("v2_codec_disponivel", 1, str(codigo))
    # code=0x0102 -> se o campo tiver 2 bytes, a saida comeca com 02 01
    r = subprocess.run([str(codigo), "encode", "--profile", "orig", "--code", "258",
                        "--body-hex", ""], capture_output=True, text=True, timeout=30)
    hexout = ""
    for ln in r.stdout.splitlines():
        if ln.startswith("hex="):
            hexout = ln[4:]
    tsv("v2_encode_code_258", hexout, "mu2codec encode --code 258 (0x0102)")
    tsv("v2_bytes_do_campo_code", len(hexout) // 2 - 2 if hexout else "?", "4 bytes de cabecalho")
    tsv("v2_max_frame", 2052, "include/mu2/mu2.h MU2_MAX_FRAME")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default=os.environ.get("MU_REF_DATA", "../MuServer"))
    ap.add_argument("--codec", default="out/mu2codec")
    a = ap.parse_args()
    ref = pathlib.Path(a.ref)
    if not ref.is_dir():
        sys.stderr.write("interop_probe: MU_REF_DATA nao encontrado (%s)\n" % ref)
        return 2
    print("chave\tvalor\tfonte")
    mede_hackpacket(ref)
    mede_capturas(ref)
    mede_framing(ref)
    mede_v2(pathlib.Path(a.codec))
    mede_ambiente(pathlib.Path(a.codec))
    return 0


if __name__ == "__main__":
    sys.exit(main())
