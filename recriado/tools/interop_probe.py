#!/usr/bin/env python3
"""interop_probe.py — evidência de interoperabilidade, SOMENTE LEITURA (Etapa A / R-6).

Não executa nenhum binário do pacote original, não abre rede e não escreve em MU_REF_DATA.
Mede o que existe em disco e o que existe no ambiente, e devolve linhas `chave<TAB>valor<TAB>fonte`
para que a suíte tests/interop.sh as cobre como asserção — evidência sem teste reproduzível vira
opinião (foi por isso que a matriz da R-6 passou a exigir comando reproduzível).

Saída: TSV em stdout. Exit 0 sempre que a referência foi lida; 2 sem MU_REF_DATA.
"""
from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

HACK = "Data/Hack/HackPacketCheck.txt"
CAPTURA_EXT = {".pcap", ".pcapng", ".cap"}
LUA_FRAMING = re.compile(r"HEAD_SIZE|PacketSize|MakePacket|opcode", re.IGNORECASE)


def tsv(chave: str, valor: str, fonte: str) -> None:
    print(f"{chave}\t{valor}\t{fonte}")


def hack_packet_check(ref: Path) -> None:
    """Tabela Index/Value/Encrypt/MaxDelay/MinCount/MaxCount do verificador anti-hack.

    É a única fonte do pacote que enumera o espaço de índices de pacote sem precisar executar
    nada. Diz quantos índices existem, quais são marcados como criptografados e que há limites de
    taxa por pacote — não é um despejo do formato de quadro, e não é tratada como tal.
    """
    p = ref / HACK
    if not p.is_file():
        tsv("hackpacketcheck_presente", "0", HACK)
        return
    tsv("hackpacketcheck_presente", "1", HACK)
    indices: list[int] = []
    enc1 = enc0 = curinga = 0
    linhas_uteis = 0
    tem_end = 0
    colunas = set()
    for raw in p.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        if line.lower() == "end":
            tem_end = 1
            continue
        f = line.split()
        colunas.add(len(f))
        if len(f) < 3 or not f[0].isdigit():
            continue
        linhas_uteis += 1
        indices.append(int(f[0]))
        if f[2] == "1":
            enc1 += 1
        elif f[2] == "0":
            enc0 += 1
        else:
            curinga += 1
    dup = len(indices) - len(set(indices))
    tsv("hackpacketcheck_entradas", str(linhas_uteis), HACK)
    tsv("hackpacketcheck_terminador_end", str(tem_end), HACK)
    tsv("hackpacketcheck_colunas_por_linha", ",".join(str(c) for c in sorted(colunas)), HACK)
    if indices:
        tsv("hackpacketcheck_index_min", str(min(indices)), HACK)
        tsv("hackpacketcheck_index_max", str(max(indices)), HACK)
        # Consequência aritmética, não interpretação: se o maior índice é 255, o campo que o
        # carrega tem no máximo 8 bits. O v2 usa 16 bits para `code` (mu2.h) — diferença registrada.
        tsv("hackpacketcheck_bits_do_espaco", str(max(indices).bit_length()), HACK)
    tsv("hackpacketcheck_encrypt_1", str(enc1), HACK)
    tsv("hackpacketcheck_encrypt_0", str(enc0), HACK)
    tsv("hackpacketcheck_encrypt_curinga", str(curinga), HACK)
    tsv("hackpacketcheck_indices_duplicados", str(dup), HACK)
    tsv("hackpacketcheck_encrypt_1_indices",
        " ".join(str(i) for i in sorted({int(f[0]) for f in
                                         (ln.split() for ln in
                                          p.read_text(encoding="utf-8", errors="replace").splitlines()
                                          if ln.strip() and not ln.startswith("//"))
                                         if len(f) >= 3 and f[0].isdigit() and f[2] == "1"})), HACK)


def capturas(ref: Path) -> None:
    n = 0
    for root, _dirs, files in os.walk(ref):
        for f in files:
            if Path(f).suffix.lower() in CAPTURA_EXT:
                n += 1
    tsv("capturas_de_trafego", str(n), "varredura *.pcap/*.pcapng/*.cap em MU_REF_DATA")


def framing_em_scripts(ref: Path) -> None:
    """Procura declaração de enquadramento na camada de script (Lua e textos de dados)."""
    hits = 0
    arquivos = 0
    for root, _dirs, files in os.walk(ref):
        for f in files:
            if Path(f).suffix.lower() not in {".lua", ".txt"}:
                continue
            arquivos += 1
            try:
                txt = (Path(root) / f).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if LUA_FRAMING.search(txt):
                hits += 1
    tsv("scripts_e_textos_varridos", str(arquivos), "MU_REF_DATA (*.lua, *.txt)")
    tsv("arquivos_com_declaracao_de_framing", str(hits), "regex HEAD_SIZE|PacketSize|MakePacket|opcode")


def ambiente() -> None:
    """O que o ambiente oferece para um teste real de interoperabilidade."""
    tsv("wine_disponivel", "1" if shutil.which("wine") or shutil.which("wine64") else "0",
        "PATH (shutil.which)")
    tsv("qemu_i386_disponivel", "1" if shutil.which("qemu-i386") else "0", "PATH")
    tsv("optin_para_executar_original", "1" if os.environ.get("MU_INTEROP_ALLOW_ORIGINAL") == "1"
        else "0", "variável MU_INTEROP_ALLOW_ORIGINAL")


def main() -> int:
    ref = Path(os.environ.get("MU_REF_DATA", str(Path(__file__).resolve().parents[2] / "MuServer")))
    if not ref.is_dir():
        print("# BLOCKED motivo=MU_REF_DATA ausente ou nao e diretorio", file=sys.stderr)
        return 2
    print("chave\tvalor\tfonte")
    hack_packet_check(ref)
    capturas(ref)
    framing_em_scripts(ref)
    ambiente()
    return 0


if __name__ == "__main__":
    sys.exit(main())
