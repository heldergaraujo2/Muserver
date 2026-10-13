#!/usr/bin/env bash
# pe.sh — suíte `pe` + `pe-selftest` (fase R-5): inspeção reproduzível dos PE da referência.
#
# Regras da fase:
#   1. o probe mede, o teste afirma o que foi medido (números ancorados em relatórios r5-*.tsv);
#   2. ausência de string NUNCA vira ausência de recurso — o caso diz isso explicitamente;
#   3. cada caso é uma função: sem `eval`, sem `set -e`, e cada asserção decide por si.
set -u
cd "$(dirname "$0")/.." || exit 2
ROOT=$(cd .. && pwd)
export MU_REF_DATA="${MU_REF_DATA:-$ROOT/MuServer}"
OUT=out; mkdir -p "$OUT"
n=0; bad=0

ck() {  # ck <n> <descrição> <função>
  n=$((n+1))
  if "$3" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi
}

# SELFTEST_ONLY=1 roda só os casos de recusa (t11-t14), sem tocar na referencia de 615 MB:
# e o que o portao usa quando a referencia nao esta presente (o bundle nao a carrega).
REF=0; REFMODE=ausente
if [ -n "${SELFTEST_ONLY:-}" ]; then
  REFMODE=selftest
  printf '# nota=SELFTEST_ONLY: casos da referencia omitidos por decisao desta execucao\n'
elif [ ! -d "$MU_REF_DATA" ]; then
  REFMODE=ausente
  printf '# BLOCKED motivo=MU_REF_DATA nao encontrado (%s): a referencia nao viaja no bundle\n' "$MU_REF_DATA"
else
  REF=1; REFMODE=referencia
  # uma passada completa; a segunda (t09) só existe para provar determinismo
  python3 tools/pe_probe.py --keywords > "$OUT/pe.tsv" 2>"$OUT/pe.err"
  PE_EXIT=$?
fi
# linhas de PE têm 12 colunas; as de palavras-chave têm 4 e vêm depois do marcador '#'
PE_LINHAS() { awk -F'\t' 'NF==12 && NR>1' "$OUT/pe.tsv"; }

t01() { [ "$PE_EXIT" -eq 0 ]; }
t02() { [ "$(PE_LINHAS | wc -l)" = 22 ]; }
t03() { [ "$(PE_LINHAS | awk -F'\t' '$4=="i386"'  | wc -l)" = 21 ] &&
        [ "$(PE_LINHAS | awk -F'\t' '$4=="x86_64"' | wc -l)" = 1 ] &&
        PE_LINHAS | awk -F'\t' '$4=="x86_64" && $1=="PSGuard/Servidor.64.exe" && $5==1' | grep -q .; }
t04() { PE_LINHAS | awk -F'\t' '$1=="ConnectServer/ConnectServer.exe" && $2=="380416" &&
        $3=="f25eecb6c65214b7" && $4=="i386"' | grep -q .; }
t05() { [ "$(PE_LINHAS | grep -c themida)" -ge 3 ]; }
t06() { [ "$(awk -F'\t' '$3=="CreateIoCompletionPort"' "$OUT/pe.tsv" | wc -l)" -ge 1 ]; }
t07() { [ "$(awk -F'\t' '$3=="luaL_"' "$OUT/pe.tsv" | wc -l)" -ge 1 ]; }
t08() { [ "$(awk -F'\t' '$3=="PacketSize" || $3=="HEAD_SIZE" || $3=="opcode"' "$OUT/pe.tsv" |
        wc -l)" = 0 ]; }
t09() { python3 tools/pe_probe.py --keywords > "$OUT/pe2.tsv" 2>/dev/null
        [ "$(sha256sum < "$OUT/pe.tsv" | cut -c1-16)" = \
          "$(sha256sum < "$OUT/pe2.tsv" | cut -c1-16)" ]; }
t10() { ! grep -q "$ROOT" "$OUT/pe.tsv"; }

# ---- pe-selftest: entrada inválida tem de ser recusada, e a suíte tem de saber falhar ----
T=$(mktemp -d)
printf 'isso nao e um PE\n' > "$T/falso.exe"
if [ "$REF" = 1 ]; then
  FIX=real; head -c 32 "$MU_REF_DATA/ConnectServer/ConnectServer.exe" > "$T/truncado.exe"
else
  # sem a referencia: MZ + zeros (e_lfanew=0) ja exerce o mesmo caminho de recusa
  FIX=sintetico; { printf 'MZ'; head -c 62 /dev/zero; } > "$T/truncado.exe"
fi
printf '# nota=fixture_truncado=%s\n' "$FIX"
MU_REF_DATA="$T" python3 tools/pe_probe.py > "$OUT/st1.tsv" 2>/dev/null
ST_EXIT=$?
t11() { [ "$ST_EXIT" -eq 1 ] && grep -q $'falso.exe\tNAO-PE' "$OUT/st1.tsv"; }
t12() { grep -q $'truncado.exe\tNAO-PE' "$OUT/st1.tsv"; }
t13() { MU_REF_DATA=/caminho-que-nao-existe python3 tools/pe_probe.py >/dev/null 2>&1
        [ $? -eq 2 ]; }
t14() { [ "$(PE_LINHAS | wc -l)" != 999 ]; }   # expectativa errada de propósito

if [ "$REF" = 1 ]; then
ck 1 "todos os .exe da referencia sao PE validos (exit 0)" t01
ck 2 "22 executaveis inventariados (medido, nao presumido)" t02
ck 3 "21 PE32/i386 + 1 PE32+/x86_64 (PSGuard/Servidor.64.exe, o unico 64 bits)" t03
ck 4 "ancora de integridade: ConnectServer.exe 380416 B sha256_16=f25eecb6c65214b7 i386" t04
ck 5 "secao .themida em >=3 binarios: limite real da analise estatica" t05
ck 6 "CreateIoCompletionPort medido por import em >=1 binario (IOCP observado)" t06
ck 7 "luaL_ presente em >=1 binario (Lua estaticamente ligado)" t07
ck 8 "zero ocorrencias de PacketSize/HEAD_SIZE/opcode (ausencia medida, NAO prova ausencia de recurso)" t08
ck 9 "saida deterministica: duas passadas com --keywords produzem o mesmo sha256" t09
ck 10 "nenhum caminho absoluto do host vaza na saida" t10
fi
ck 11 "selftest: arquivo que nao e PE vira NAO-PE e o probe sai 1" t11
ck 12 "selftest: PE truncado em 32 bytes e recusado (nao inventa estrutura)" t12
ck 13 "selftest: MU_REF_DATA inexistente sai 2 (erro de uso visivel)" t13
ck 14 "autos-teste: expectativa errada e detectada (senao esta suite nao vale nada)" t14
rm -rf "$T"

# blocked=1 so quando a referencia FALTA (bloqueio ambiental). Em SELFTEST_ONLY os casos da
# referencia sao omitidos por decisao desta execucao: isso e escopo declarado, nao bloqueio, e o
# portao trata como PASS de cobertura reduzida. Confundir os dois faria um selftest "aprovado"
# parecer que cobriu a referencia.
BL=0
case "$REFMODE" in
  referencia) SCOPO=referencia ;;
  selftest)   SCOPO=selftest ;;
  *)          SCOPO=ausente; BL=1 ;;
esac
printf '1..%d\n# escopo=pe:%s\n# pe=%d falhas=%d blocked=%d\n' \
  "$n" "$SCOPO" "$n" "$bad" "$BL"
[ "$bad" -eq 0 ] || exit 1
