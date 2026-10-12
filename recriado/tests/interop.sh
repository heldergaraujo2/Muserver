#!/usr/bin/env bash
# interop.sh — interoperabilidade: as TRÊS camadas separadas, sem misturá-las (Etapa A / R-6).
#
#   camada 1  conformidade interna do protocolo v2      -> comprovada (conform.sh, golden)
#   camada 2  compatibilidade entre implementações próprias -> comprovada no que existe (só o v2)
#   camada 3  compatibilidade com os executáveis originais  -> BLOCKED, com a causa exata
#
# Nenhuma camada é prova da seguinte. Esta suíte NUNCA executa binário do pacote original: a
# camada 3 só roda com MU_INTEROP_ALLOW_ORIGINAL=1 E wine presente; sem isso ela reporta BLOCKED
# com o que falta, e o portão mostra BLOCKED — que não é PASS nem FAIL.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
REF=${MU_REF_DATA:-$V2/../MuServer}
PROBE=$V2/tools/interop_probe.py
CLI=$V2/out/mu2codec
n=0; bad=0; BL=0
ck() { n=$((n+1)); if "${@:3}" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

[ -f "$PROBE" ] || { printf '1..0\n# interop=0 falhas=0 blocked=1\n# BLOCKED motivo=tools/interop_probe.py ausente\n'; exit 0; }
command -v python3 >/dev/null 2>&1 || {
  printf '1..0\n# interop=0 falhas=0 blocked=1\n# BLOCKED motivo=python3 ausente\n'; exit 0; }
if [ ! -d "$REF" ]; then
  printf '1..0\n# interop=0 falhas=0 blocked=1\n# BLOCKED motivo=MU_REF_DATA ausente (%s)\n' "$REF"
  exit 0
fi

EV=$(MU_REF_DATA="$REF" python3 "$PROBE" 2>/dev/null); RC_EV=$?
if [ "$RC_EV" -ne 0 ]; then
  printf '1..0\n# interop=0 falhas=0 blocked=1\n# BLOCKED motivo=sonda de evidencia saiu %d\n' "$RC_EV"
  exit 0
fi
val() { printf '%s\n' "$EV" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'; }

printf '# escopo=interop:3-camadas-separadas\n'
printf '# aviso=camada 1 nao prova camada 2, camada 2 nao prova camada 3\n'

# ---------------------------------------------------------------- camada 2: evidência medida
ENTRADAS=$(val hackpacketcheck_entradas)
IMIN=$(val hackpacketcheck_index_min)
IMAX=$(val hackpacketcheck_index_max)
BITS=$(val hackpacketcheck_bits_do_espaco)
ENC1=$(val hackpacketcheck_encrypt_1)
CAPT=$(val capturas_de_trafego)
FRAM=$(val arquivos_com_declaracao_de_framing)
VARR=$(val scripts_e_textos_varridos)
t01() { [ "$ENTRADAS" = 272 ] && [ "$IMIN" = 0 ] && [ "$IMAX" = 255 ]; }
ck 1 "camada2 HackPacketCheck enumera 272 entradas com indice 0..255 (medido, sem executar nada)" t01
t02() { [ "$BITS" = 8 ]; }
ck 2 "camada2 o espaco de indices do original cabe em 8 bits (max 255 => bit_length 8)" t02
t03() { [ "$ENC1" = 37 ]; }
ck 3 "camada2 37 entradas marcadas Encrypt=1 (35 indices distintos; 77/78/236 se repetem)" t03
t04() { [ "$CAPT" = 0 ]; }
ck 4 "camada2 zero capturas de trafego no pacote: nao ha tráfego original observado para comparar" t04
t05() { [ "$FRAM" = 0 ] && [ "$VARR" -gt 1000 ]; }
ck 5 "camada2 nenhuma declaracao de framing em $VARR scripts/textos (HEAD_SIZE|PacketSize|MakePacket|opcode)" t05

# ---------------------------------------------------------------- v2 × original: diferença medida
# O v2 tem code de 16 bits (mu2.h: header = code(2 LE) + size(2 LE)). O vetor golden G-25 prova que
# um size de 256 ocupa dois bytes (00 01). Num espaco de indices de 8 bits esse campo nao existe.
# Isto e diferenca medida, nao opinião — e NAO e prova de incompatibilidade total: e prova de que
# o cabecalho do v2 nao e o cabecalho do original neste aspecto.
# O quadro vem do corpus versionado (G-25), não de um hex escrito aqui: se alguém mudar o vetor,
# esta asserção muda junto, em vez de ficar comparando com um valor solto.
G25=$(awk -F'\t' '$1=="G-25"{print $6}' "$V2/tests/golden/quadros.tsv")
CODESIZE=$("$CLI" decode --profile orig --in-hex "$G25" 2>/dev/null | sed -n 's/^decode=//p' | cut -d: -f2)
t06() { [ "$CODESIZE" = 256 ]; }
ck 6 "v2 le size=256 em dois bytes little-endian (00 01) — 16 bits, contra 8 bits do original" t06
t07() { [ "$BITS" = 8 ] && [ "$CODESIZE" = 256 ]; }
ck 7 "conclusao permitida: o cabecalho do v2 difere do espaco de indices do original (8 vs 16 bits)" t07

# ---------------------------------------------------------------- camada 3: o teste real
WINE=$(val wine_disponivel)
QEMU=$(val qemu_i386_disponivel)
OPTIN=$(val optin_para_executar_original)
FALTA=""
[ "$WINE" = 1 ] || FALTA="${FALTA}wine(ausente) "
[ "$OPTIN" = 1 ] || FALTA="${FALTA}MU_INTEROP_ALLOW_ORIGINAL=1(nao autorizado) "
# O binário de entrada é PE32/i386 (medido na R-5 por tests/pe.sh); sem wine nem qemu-i386 não há
# como executá-lo aqui, e executá-lo automaticamente é proibido pelas regras do projeto.
if [ -n "$FALTA" ]; then
  BL=1
  printf '# BLOCKED motivo=%s\n' "${FALTA% }"
  printf '# BLOCKED dependencia=ConnectServer.exe e PE32/i386 com secoes .themida; executa-lo exige\n'
  printf '#   wine ou qemu-i386 + autorizacao explicita do dono. Condicao de desbloqueio: um desses\n'
  printf '#   ambientes existir E MU_INTEROP_ALLOW_ORIGINAL=1. Nenhuma conexao original e simulada.\n'
  printf '# camada3=nao_testada (ausencia de evidencia nao vira compatibilidade afirmada)\n'
else
  # Caminho real, só com autorização explícita. Mantido mínimo de propósito: subir o original é
  # decisão do dono, e esta suíte não toma essa decisão sozinha.
  printf '# camada3=autorizada: executando teste real contra o binario original\n'
  bad=$((bad + 1))
  printf 'not ok %d - camada3 teste real ainda nao implementado (autorizacao sem procedimento escrito)\n' \
    "$((n + 1))"
  n=$((n + 1))
fi

printf '1..%d\n' "$n"
printf '# interop=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# camadas: 1=comprovada(conform/golden) 2=evidencia medida acima 3=%s\n' \
  "$( [ "$BL" = 1 ] && echo BLOCKED || echo em_andamento )"
[ "$bad" -eq 0 ] || exit 1
