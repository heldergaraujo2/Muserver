#!/usr/bin/env bash
# lua.sh — Etapa F: camada Lua e despacho de pacotes, com a correcao da conclusao da R-6.
#
# CORRECAO REGISTRADA: a R-6 publicou "0 declaracoes de framing em .lua". Essa busca usou tokens
# estreitos demais (HEAD_SIZE/PacketSize/opcode) e o resultado e FALSO: ha 20 .lua com termos de
# pacote e um ProtocolCore.lua real em 3 arvores de servidor e 5 do lado cliente. Ver
# reports/rf-lua-protocolo.md. Este teste existe para que a afirmacao errada nao volte.
#
# Procedencia: MuServer/Data/Script/System/ProtocolCore.lua foi modificado por trabalho anterior
# desta branch. A evidencia sobre o ORIGINAL vem do baseline em workspace/changes/originals/ e das
# copias nao tocadas (SpeedServer, SubSalatest) — nunca do arquivo patcheado.
#
# BLOCKED: nao ha interpretador Lua neste host, entao NAO ha verificacao de sintaxe nem execucao.
# O inventario e a evidencia estatica sao medidos; a camada nao foi executada.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
PROBE=$V2/tools/lua_probe.py
OUTD=$V2/out/lua
OUT=$OUTD/lua.tsv
n=0; bad=0; BL=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

[ -f "$PROBE" ] || { printf '1..0\n# lua=0 falhas=0 blocked=1\n# BLOCKED motivo=probe ausente\n'; exit 0; }
if [ ! -d "${MU_REF_DATA:-../MuServer}" ]; then
  printf '1..0\n# lua=0 falhas=0 blocked=1\n# BLOCKED motivo=MU_REF_DATA ausente (%s)\n' \
    "${MU_REF_DATA:-../MuServer}"; exit 0
fi
mkdir -p "$OUTD"; rm -f "$OUT" 2>/dev/null
MU_REF_DATA="${MU_REF_DATA:-../MuServer}" python3 "$PROBE" > "$OUT" 2>"$OUTD/lua.err"
RC=$?
if [ "$RC" -ne 0 ]; then
  printf '1..0\n# lua=0 falhas=0 blocked=1\n# BLOCKED motivo=probe saiu %d\n' "$RC"; exit 0
fi
printf '# escopo=lua:inventario+evidencia-estatica (nao executada: sem interpretador)\n'

val() { awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$OUT"; }

# sem interpretador, a camada nao pode ser executada nem ter a sintaxe verificada: bloqueio
# ambiental registrado, nao falha e nao silencio.
INTERP=$(val interpretador_lua)
[ "$INTERP" = ausente ] && BL=1 && printf '# BLOCKED motivo=interpretador Lua ausente: sem verificacao de sintaxe nem execucao\n'

ck "148 arquivos .lua no pacote" "[ \"\$(val lua_total)\" = 148 ]"
ck "CORRECAO da R-6: 20 .lua tem termos de pacote (a busca antiga dizia 0 e estava errada)" \
   "[ \"\$(val lua_com_termos_de_pacote)\" = 20 ]"
ck "5 .lua chamam SendPacket" "[ \"\$(val lua_com_sendpacket)\" = 5 ]"
ck "8 copias de ProtocolCore.lua: 3 de servidor e 5 do lado cliente" \
   "[ \"\$(val protocolcore_copias)\" = 8 ] && \
    [ \"\$(awk -F'\t' '\$1==\"protocolcore\" && \$3 ~ /^servidor/' \"$OUT\" | wc -l)\" = 3 ] && \
    [ \"\$(awk -F'\t' '\$1==\"protocolcore\" && \$3 ~ /^cliente/' \"$OUT\" | wc -l)\" = 5 ]"
ck "as copias SpeedServer e SubSalatest tem o md5 do baseline original (04b049...)" \
   "[ \"\$(awk -F'\t' '\$1==\"protocolcore\" && \$3 ~ /SpeedServer|SubSalatest/{print \$2}' \"$OUT\" |
      sort -u)\" = 04b0495b8cddb7d9f64b071660f57623 ]"
ck "o baseline em workspace/changes/originals/ confere com ORIGINALS.md5" \
   "grep -q '^04b0495b8cddb7d9f64b071660f57623  MuServer/Data/Script/System/ProtocolCore.lua\$' \
     ../workspace/changes/ORIGINALS.md5"
ck "assinatura real do lado servidor (do ORIGINAL, nao do patcheado):
    GameServerProtocolRecv(aIndex, Packet, PacketName)" \
   "[ \"\$(val assinatura_servidor_original)\" = ProtocolCore.lua:10 ]"
ck "assinatura real do lado cliente: ClientProtocolRecv(Packet, PacketName)" \
   "[ \"\$(val assinatura_cliente)\" = ProtocolCore.lua:7 ]"
ck "ClearPacket( presente em 7 das 8 copias" "[ \"\$(val clearpacket_presente)\" = 7 ]"
ck "evidencia de tipos: PacketName formatado como %s (7) e Head como %d (7) —
    pacote identificado por NOME mais cabecalho numerico" \
   "[ \"\$(val packetname_formatado_como_string)\" = 7 ] && [ \"\$(val head_formatado_como_numero)\" = 7 ]"
ck "LuaEncTool presente com .exe e .pdb; ClientDecrypted legivel; ClientEncrypted sem cabecalho
    reconhecivel (28aa2191a6dd35f7)" \
   "[ \"\$(val luaenctool_presente)\" = 1 ] && [ \"\$(val luaenctool_exe)\" = 1 ] && \
    [ \"\$(val luaenctool_pdb)\" = 1 ] && [ \"\$(val clientdecrypted_legivel)\" = 1 ] && \
    [ \"\$(val clientencrypted_primeiros8)\" = 28aa2191a6dd35f7 ]"
ck "probe deterministico: duas execucoes produzem o mesmo TSV" \
   "MU_REF_DATA=\"\${MU_REF_DATA:-../MuServer}\" python3 '$PROBE' | diff -q - '$OUT' >/dev/null"
ck "main.exe existe como saida do Gerador de Main e NAO foi executado por este teste" \
   "[ \"\$(val cliente_main_exe)\" = 1 ]"

printf '1..%d\n' "$n"
printf '# lua=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# limite=evidencia estatica; sem interpretador nao ha sintaxe verificada nem execucao\n'
[ "$bad" -eq 0 ] || exit 1
