#!/usr/bin/env bash
# fuzz.sh — fuzzing determinístico do codec v2 (Etapa B).
#
# Motor: tools/mu2fuzz.c sobre out/wire.o (o codec real). Não há motor de fuzz neste host —
# medido: sem afl-fuzz, honggfuzz, radamsa, clang, e gcc 12 não aceita -fsanitize=fuzzer. Esta é
# uma alternativa DETERMINÍSTICA: sequência reproduzível de mutações a partir de sementes, julgada
# por um oráculo de invariantes do contrato. **Não é cobertura equivalente a um fuzzer dedicado**
# (não há feedback de bordas), e a ferramenta diz isso na própria saída.
#
# Sementes vêm do corpus golden: o fuzz parte do que é sabidamente válido, não do vazio.
# Sanitizadores do build (ASan+UBSan, -fno-sanitize-recover=all) dão detecção de crash: morte por
# sinal aparece como exit >= 128 e é tratada como falha, nunca como "passou".
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$V2" || exit 2
FZ=$V2/out/mu2fuzz; CLI=$V2/out/mu2codec; CORPUS=$V2/tests/golden/quadros.tsv
OUTD=$V2/out/fuzz
ITERS=${FUZZ_ITERS:-50000}
n=0; bad=0; BL=0
ck() { n=$((n+1)); if "${@:3}" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

for b in "$FZ" "$CLI"; do
  [ -x "$b" ] || { printf '1..0\n# fuzz=0 falhas=0 blocked=1\n# BLOCKED motivo=falta %s (make build)\n' "$b"; exit 0; }
done
[ -f "$CORPUS" ] || { printf '1..0\n# fuzz=0 falhas=0 blocked=1\n# BLOCKED motivo=corpus golden ausente\n'; exit 0; }
command -v cc >/dev/null 2>&1 || {
  printf '1..0\n# fuzz=0 falhas=0 blocked=1\n# BLOCKED motivo=cc ausente (F22 precisa compilar o mutante)\n'; exit 0; }

mkdir -p "$OUTD"; rm -f "$OUTD"/regressao-*.hex 2>/dev/null
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# sementes: coluna `entrada` do corpus, fora os marcadores '-' e VAZIO
SEEDS=()
while IFS= read -r h; do
  [ -n "$h" ] && SEEDS+=(--seed-hex "$h")
done < <(awk -F'\t' '$1!~/^#/ && $1!="id" && $6!="-" && $6!="VAZIO" {print $6}' "$CORPUS" | sort -u)
printf '# escopo=fuzz:codec-v2-deterministico\n'
printf '# sementes_do_corpus=%d iteracoes_por_rodada=%s\n' "${#SEEDS[@]}" "$ITERS"
[ "${#SEEDS[@]}" -gt 0 ] || { printf '1..0\n# fuzz=0 falhas=0 blocked=1\n# BLOCKED motivo=nenhuma semente extraida do corpus\n'; exit 0; }

rodada() {  # rodada <rotulo> <seed> <max-bytes> [extra...]
  local rot=$1 seed=$2 mb=$3; shift 3
  "$FZ" --seed "$seed" --iters "$ITERS" --max-bytes "$mb" --saida-dir "$OUTD" \
        "${SEEDS[@]}" "$@" > "$OUTD/$rot.txt" 2>&1
  echo $?
}

RC1=$(rodada r1 1 300)
RC3=$(rodada r3 12345 2052)

# Limite de memória de verdade exige build SEM sanitizadores: o ASan reserva uma sombra enorme e
# não sobrevive a RLIMIT_AS. Medido, não suposto — a asserção 3 abaixo fixa esse fato.
NOSAN=$TMPD/nosan; mkdir -p "$NOSAN"
cc -std=c11 -O2 -g -Wall -Wextra -Werror -Iinclude -c "$V2/src/wire.c" -o "$NOSAN/wire.o" 2>"$NOSAN/cc.log" &&
  cc -std=c11 -O2 -g -Wall -Wextra -Werror -Iinclude "$V2/tools/mu2fuzz.c" "$NOSAN/wire.o" \
     -o "$NOSAN/mu2fuzz" 2>>"$NOSAN/cc.log"
if [ -x "$NOSAN/mu2fuzz" ]; then
  "$NOSAN/mu2fuzz" --seed 7 --iters "$ITERS" --max-bytes 300 --mem-limit-mb 64 \
    --saida-dir "$OUTD" "${SEEDS[@]}" > "$OUTD/r2.txt" 2>&1
  RC2=$?
else
  RC2=2
fi
"$FZ" --seed 7 --iters 100 --max-bytes 64 --mem-limit-mb 512 --saida-dir "$OUTD" \
  > "$OUTD/r2-asan.txt" 2>&1
RC2_ASAN=$?

t01() { [ "$RC1" = 0 ]; }
ck 1 "rodada 1 (semente 1, até 300 B): 0 violações de invariante, sem morte por sanitizador" t01
t02() { [ "$RC2" = 0 ]; }
ck 2 "rodada 2 (semente 7, RLIMIT_AS 64 MB em build sem ASan): 0 violações com limite de memória" t02
t03() { [ "$RC2_ASAN" -ne 0 ] && grep -qi 'mmap' "$OUTD/r2-asan.txt"; }
ck 3 "medido: RLIMIT_AS 512 MB derruba o build com ASan (Failed to mmap) — por isso o limite roda sem ASan" t03
t04() { [ "$RC3" = 0 ]; }
ck 4 "rodada 3 (semente 12345, até 2052 B = quadro máximo): 0 violações" t04
t05() { [ "$RC1" -lt 128 ] && [ "$RC2" -lt 128 ] && [ "$RC3" -lt 128 ]; }
ck 5 "nenhuma rodada morreu por sinal (exit < 128): crash seria falha, não silêncio" t05
t06() { ! ls "$OUTD"/regressao-*.hex >/dev/null 2>&1; }
ck 6 "nenhum caso de regressão produzido pelo codec real (diretório de regressões vazio)" t06

# determinismo: mesma semente, mesma sequência — sem isso "reproduzível" é palavra vazia
"$FZ" --seed 99 --iters 5000 --max-bytes 300 --saida-dir "$OUTD" "${SEEDS[@]}" > "$OUTD/d1.txt" 2>&1
"$FZ" --seed 99 --iters 5000 --max-bytes 300 --saida-dir "$OUTD" "${SEEDS[@]}" > "$OUTD/d2.txt" 2>&1
t06() { diff -q <(grep -E '^(operadores=|iteracoes=)' "$OUTD/d1.txt") \
                <(grep -E '^(operadores=|iteracoes=)' "$OUTD/d2.txt") >/dev/null; }
ck 7 "determinismo: duas execuções com a mesma semente produzem a mesma sequência" t06
# a linha é operadores=nome=QTD,nome=QTD,... => com -F'[=,]' os contadores caem nos campos ímpares
t08() { [ "$(awk -F'[=,]' '/^operadores=/{for(i=3;i<=NF;i+=2) if($i+0>0) c++} END{print c+0}' \
        "$OUTD/r1.txt")" = 10 ]; }
ck 8 "os 10 operadores de mutação foram exercitados (nenhum ficou sem uso)" t08

# ---------------------------------------------------------------- F22: o oráculo tem dentes?
# Sem isto, "0 violações" não vale nada: o oráculo poderia ser incapaz de falhar. O codec é mutado
# em CÓPIA TEMPORÁRIA (src/wire.c nunca é tocado): remove-se o piso `size < 4`, e o fuzzer tem de
# achar. Depois, a entrada que derrubou o mutante é replayada no codec real e tem de ser recusada.
MUTW=$TMPD/wire.c
sed 's/if (size < (uint16_t)MU2_HEADER_SIZE || size > (uint16_t)MU2_MAX_FRAME)/if (size > (uint16_t)MU2_MAX_FRAME) \/* F22 *\//' \
  "$V2/src/wire.c" > "$MUTW"
FLAGS=$(make -s dump-CFLAGS 2>/dev/null)
MUTBIN=$TMPD/mu2fuzz-mutado
if grep -q 'F22' "$MUTW" && cc $FLAGS -c "$MUTW" -o "$TMPD/wire.o" 2>"$TMPD/cc.log" &&
   cc $FLAGS "$V2/tools/mu2fuzz.c" "$TMPD/wire.o" -o "$MUTBIN" \
      -fsanitize=address,undefined 2>>"$TMPD/cc.log"; then
  mkdir -p "$TMPD/reg"
  "$MUTBIN" --seed 1 --iters "$ITERS" --max-bytes 300 --saida-dir "$TMPD/reg" \
    "${SEEDS[@]}" > "$TMPD/mut.txt" 2>&1
  RC_MUT=$?
  PRIMEIRA=$(sed -n 's/^violacao .*entrada=//p' "$TMPD/mut.txt" | head -1)
  t09() { [ "$RC_MUT" = 3 ] && grep -q '^violacao ' "$TMPD/mut.txt"; }
  ck 9 "F22 codec mutado (sem o piso size>=4) é pego pelo oráculo: violações > 0" t09
  t10() { [ -n "$PRIMEIRA" ] && ls "$TMPD"/reg/regressao-*.hex >/dev/null 2>&1; }
  ck 10 "F22 a violação gera caso de regressão gravado em disco com a entrada exata" t10
  # replay no codec REAL: o que derrubou o mutante tem de ser recusado aqui
  if [ -n "$PRIMEIRA" ]; then
    R=$("$CLI" decode --profile orig --in-hex "$PRIMEIRA" 2>/dev/null)
    printf '# F22 replay no codec real: entrada=%s erro=%s\n' "$PRIMEIRA" \
      "$(printf '%s' "$R" | sed -n 's/^erro=//p')"
    t11() { printf '%s' "$R" | grep -q '^classe=malformado$'; }
    ck 11 "F22 replay: o codec real recusa a entrada que derrubou o mutante (classe=malformado)" t11
  else
    bad=$((bad + 1)); printf 'not ok %d - F22 mutante nao produziu entrada para replay\n' "$((n + 1))"
    n=$((n + 1))
  fi
else
  BL=1
  printf '# BLOCKED motivo=F22 nao compilou o mutante (ver log abaixo)\n'
  sed 's/^/# cc: /' "$TMPD/cc.log" 2>/dev/null | head -5
fi
t12() { git -C "$V2/.." diff --quiet -- recriado/src/wire.c; }
ck 12 "src/wire.c permanece inalterado (a mutação viveu só na cópia temporária)" t12

soma() { sed -n 's/^iteracoes=\([0-9]*\).*/\1/p' "$1" 2>/dev/null | head -1; }
TOTAL=$(( $(soma "$OUTD/r1.txt") + $(soma "$OUTD/r2.txt") + $(soma "$OUTD/r3.txt") ))
printf '1..%d\n' "$n"
printf '# fuzz=%d falhas=%d blocked=%d\n' "$n" "$bad" "$BL"
printf '# iteracoes_totais=%s sementes=%d motor=proprio-deterministico\n' "$TOTAL" "${#SEEDS[@]}"
printf '# aviso=sem cobertura guiada por feedback (nao ha afl/clang neste host); nao equivale a fuzzer dedicado\n'
[ "$bad" -eq 0 ] || exit 1
