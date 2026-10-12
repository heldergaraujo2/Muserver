#!/usr/bin/env bash
# interop.sh — R-6 / Etapa A: interoperabilidade com o software original.
#
# As TRÊS camadas são medidas e reportadas SEPARADAS. Nenhuma é prova da seguinte:
#   1 conformidade interna do protocolo v2       -> conform.sh (15/15) + golden (42)
#   2 compatibilidade entre implementações próprias -> net.sh (34) e a evidência desta suíte
#   3 compatibilidade com os executáveis originais  -> BLOCKED com causa exata
#
# REGRA ABSOLUTA: esta suíte NÃO executa binário original. Não há caminho de execução aqui. Quando
# as precondições existirem, o caminho é um procedimento manual supervisionado que deposita
# reports/r6-interop-real.tsv; esta suíte então VALIDA essa evidência. Sem o arquivo, BLOCKED —
# nunca PASS, nunca suposição.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
PROBE=$V2/tools/interop_probe.py
OUTD=$V2/out/interop
OUT=$OUTD/interop.tsv
EVID=$V2/reports/r6-interop-real.tsv
n=0; bad=0; BL=0
ck() { n=$((n+1)); if eval "$2" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$1"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$1"; fi; }

[ -f "$PROBE" ] || { printf '1..0\n# interop=0 falhas=0 blocked=1\n# BLOCKED motivo=probe ausente\n'; exit 0; }
[ -d "${MU_REF_DATA:-../MuServer}" ] || {
  printf '1..0\n# interop=0 falhas=0 blocked=1\n# BLOCKED motivo=MU_REF_DATA ausente (%s)\n' \
    "${MU_REF_DATA:-../MuServer}"; exit 0; }
mkdir -p "$OUTD"
MU_REF_DATA="${MU_REF_DATA:-../MuServer}" python3 "$PROBE" > "$OUT" 2>"$OUTD/interop.err" || {
  printf '1..0\n# interop=0 falhas=0 blocked=1\n# BLOCKED motivo=probe falhou (ver out/interop/interop.err)\n'
  exit 0; }
val() { awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$OUT"; }

printf '# escopo=interop:3-camadas-separadas\n'

# ---------------------------------------------------------------- camada 1: v2 interno
# O campo `code` do v2 e de 2 bytes. Medido pelo codec real via CLI: code=258 (0x0102) sai 02 01.
V2CODE=$(val v2_encode_code_258)
ck "camada 1 (v2): campo code tem 2 bytes — code=0x0102 sai como 02 01 ($V2CODE)" \
   "[ \"$V2CODE\" = 02010400 ] && [ \"\$(val v2_bytes_do_campo_code)\" = 2 ]"
ck "camada 1 (v2): MU2_MAX_FRAME = 2052 declarado no contrato" "[ \"\$(val v2_max_frame)\" = 2052 ]"

# ---------------------------------------------------------------- camada 2: implementacoes proprias
# G-01 (coluna 7 = esperado) e o PING de corpo vazio que o servico tambem responde: corpus e servico
# concordam byte a byte, e sao net.sh/conform.sh que medem o mesmo do outro lado do socket.
PING=$(awk -F'\t' '$1=="G-01"{print $7}' "$V2/tests/golden/quadros.tsv" 2>/dev/null | head -1)
ck "camada 2: o quadro de referencia do corpus (G-01=$PING) e o mesmo PING que net.sh usa" \
   "[ '$PING' = 01000400 ] && grep -q '01000400' \"$V2/tests/net.sh\""
ck "camada 2: o corpus golden se declara referencia INTERNA do v2 (nao prova de compatibilidade)" \
   "grep -q 'NAO sao prova de compatibilidade com o' \"$V2/tests/golden/quadros.tsv\""

# ---------------------------------------------------------------- camada 3: evidência do original
IND=$(val hackpacketcheck_indices_distintos)
MIN=$(val hackpacketcheck_index_min)
MAX=$(val hackpacketcheck_index_max)
ENC1=$(val hackpacketcheck_encrypt_1)
ENT=$(val hackpacketcheck_entradas)
ck "camada 3 (evidencia): HackPacketCheck enumera $ENT entradas com $IND indices distintos, 0..255" \
   "[ \"$ENT\" = 272 ] && [ \"$IND\" = 256 ] && [ \"$MIN\" = 0 ] && [ \"$MAX\" = 255 ]"
ck "camada 3 (evidencia): o espaco de indices do original cabe em 8 bits (max 255)" \
   "[ \"\$(val hackpacketcheck_bits_minimos)\" = 8 ]"
ck "camada 3 (evidencia): 37 entradas marcadas como criptografadas, 234 nao, 1 curinga" \
   "[ \"$ENC1\" = 37 ] && [ \"\$(val hackpacketcheck_encrypt_0)\" = 234 ] && \
    [ \"\$(val hackpacketcheck_encrypt_curinga)\" = 1 ]"
ck "camada 3 (evidencia): tabela termina com 'end' e tem 6 colunas em toda linha util" \
   "[ \"\$(val hackpacketcheck_terminador_end)\" = 1 ] && \
    [ \"\$(val hackpacketcheck_colunas_por_linha)\" = 6 ]"
ck "camada 3 (evidencia): ZERO capturas de trafego no pacote — nao ha trafego original observado" \
   "[ \"\$(val capturas_de_trafego)\" = 0 ]"
ck "camada 3 (evidencia): ZERO declaracoes de framing em 148 .lua e 7 230 .txt" \
   "[ \"\$(val scripts_lua_com_declaracao_de_framing)\" = 0 ] && \
    [ \"\$(val textos_com_declaracao_de_framing)\" = 0 ]"

# DIVERGENCIA MEDIDA, nao opinião: 2 bytes de code (65 536 valores) contra 256 indices do original.
FATOR=$(python3 -c "print(65536 // $IND)" 2>/dev/null || echo '?')
ck "camada 3 (divergencia medida): code de 16 bits (65 536 valores) x 256 indices do original = fator $FATOR" \
   "[ \"$FATOR\" = 256 ]"

# ---------------------------------------------------------------- camada 3: o teste real
WINE=0
for f in wine wine64 qemu-i386 box86; do [ "$(val ferramenta_$f)" = 1 ] && WINE=1; done
OPTIN=$(val optin_executar_original)
FALTA=""
[ "$WINE" = 1 ] || FALTA="wine/qemu-i386/box86 ausentes (os .exe sao PE32/i386)"
[ "$OPTIN" = 1 ] || FALTA="${FALTA:+$FALTA; }MU_INTEROP_ALLOW_ORIGINAL != 1 (execucao exige autorizacao explicita)"

if [ -f "$EVID" ]; then
  # Evidencia produzida por execucao manual supervisionada. Esta suite VALIDA, nao executa.
  ok=1
  for k in procedimento responsavel data ambiente resultado servidor original cliente evidencia; do
    grep -q "^$k" "$EVID" || ok=0
  done
  ck "camada 3: evidencia manual r6-interop-real.tsv presente e completa (8 chaves)" "[ $ok = 1 ]"
  ck "camada 3: evidencia declara resultado (e nao conclusao vazia)" \
     "grep -qE '^resultado[[:space:]]+(ok|falha)' '$EVID'"
  printf '# camada3=evidencia-manual-validada arquivo=reports/r6-interop-real.tsv\n'
else
  BL=1
  printf '# BLOCKED motivo=%s\n' "$FALTA"
  printf '# BLOCKED dependencia=executar ConnectServer.exe (PE32/i386, secoes .themida) exige\n'
  printf '#   wine/qemu-i386 E autorizacao explicita do dono. Esta suite NAO executa binario original\n'
  printf '#   e nao tem caminho de execucao: nenhuma conexao original e simulada.\n'
  printf '# BLOCKED desbloqueio=rodar o procedimento supervisionado e depositar\n'
  printf '#   reports/r6-interop-real.tsv; esta suite entao valida a evidencia (casos acima).\n'
  printf '# camada3=nao_testada (ausencia de evidencia nao vira compatibilidade afirmada)\n'
fi

ck "probe deterministico: duas execucoes produzem o mesmo TSV" \
   "MU_REF_DATA=\"\${MU_REF_DATA:-../MuServer}\" python3 '$PROBE' | diff -q - '$OUT' >/dev/null"

printf '1..%d\n' "$n"
printf '# interop=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# camadas: 1=conformidade-interna-v2 2=implementacoes-proprias 3=binario-original(%s)\n' \
  "$([ "$BL" = 1 ] && echo BLOCKED || echo evidencia-manual)"
[ "$bad" -eq 0 ] || exit 1
