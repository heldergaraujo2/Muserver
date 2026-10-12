#!/usr/bin/env bash
# gate_state.sh — testa o PORTÃO (tests/run_all.sh). Um portão que não sabe falhar não é portão.
#
# Ordem: primeiro os casos sintéticos (rápidos, sem a referência de 615 MB), depois o portão real.
# As falsificações F12–F14 são DIFERENCIAIS: em vez de mutar o arquivo real e torcer para a
# reversão rodar (foi exatamente assim que a R-4 perdeu uma rodada inteira), cada mutação vive numa
# cópia em diretório temporário e o caso afirma a DIFERENÇA de comportamento entre a cópia mutada e
# o portão verdadeiro. Se um dia a detecção deixar de depender do mecanismo testado, os dois lados
# passam a concordar e o caso falha.
set -u
V2=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(cd "$V2/.." && pwd)
GATE=$V2/tests/run_all.sh
T=$(mktemp -d)
# Falha intermitente que some junto com o diretorio temporario e indiagnosticavel — aconteceu: o
# caso do portao real falhou 1 vez em ~5 execucoes e nao deixou nada para examinar. Se qualquer
# caso falhar, o temporario inteiro e copiado para out/gate-selftest-falha/ antes de ser apagado.
EVID=$V2/out/gate-selftest-falha
trap 'if [ "$bad" -gt 0 ]; then rm -rf "$EVID"; mkdir -p "$EVID"
        cp -a "$T/." "$EVID/" 2>/dev/null
        printf "# evidencia_preservada=out/gate-selftest-falha (casos_falharam=%d)\n" "$bad"
      fi; rm -rf "$T"' EXIT
n=0; bad=0
ck() { n=$((n+1)); if "$3" >/dev/null 2>&1; then printf 'ok %d - %s\n' "$n" "$2"
  else bad=$((bad+1)); printf 'not ok %d - %s\n' "$n" "$2"; fi; }

# --------------------------------------------------------------- fixtures
mk_suite() {  # mk_suite <nome> <comportamento>
  local nome=$1 modo=$2 f=$T/suites/$1.sh
  mkdir -p "$T/suites"
  case "$modo" in
    falha)     printf '#!/bin/sh\necho "1..1"\necho "# %s=1 falhas=1"\nexit 1\n' "$nome" > "$f";;
    bloqueada) printf '#!/bin/sh\necho "1..3"\necho "# %s=3 falhas=0 blocked=1"\nexit 0\n' "$nome" > "$f";;
    verde)     printf '#!/bin/sh\necho "1..2"\necho "# %s=2 falhas=0 blocked=0"\nexit 0\n' "$nome" > "$f";;
    mudo)      printf '#!/bin/sh\nexit 0\n' > "$f";;                 # sai 0 sem dizer nada
    # sai !=0 DEPOIS de imprimir resumo limpo: e o caso que so o exit code pega (a suite morreu
    # no fim, por exemplo). Se a fixture tambem reportasse falhas>0, a contagem ja detectaria e a
    # falsificacao F12 nao isolaria nada.
    falha_calada) printf '#!/bin/sh\necho "1..5"\necho "# %s=5 falhas=0 blocked=0"\nexit 3\n' "$nome" > "$f";;
    lento)     printf '#!/bin/sh\nsleep 45 &\nwait $!\n' > "$f";;     # filho próprio: testa a varredura
  esac
  chmod +x "$f"
}
mk_reg() {  # mk_reg <nome> <tipo> <rotulo> <arquivo> <obrig> <ferr> <timeout> <comando>
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" > "$T/reg.tsv"
}
# gate_run <dir_saida> [VAR=valor ...] — roda o portao com o registro atual; RC fica em $GATE_RC
GATE_RC=0
gate_run() {
  local out=$1; shift
  mkdir -p "$out"
  env GATE_SUITES="$T/reg.tsv" GATE_OUT="$out" GATE_ROOT="$V2" "$@" \
    bash "$GATE" > "$out/stdout" 2>&1
  GATE_RC=$?
}
row() { awk -F'\t' -v n="$1" '$1==n {print $2}' "$2/gate.tsv"; }
campo() { awk -F'\t' -v n="$1" -v c="$2" 'NR==1{for(i=1;i<=NF;i++) if($i==c) k=i} $1==n{print $k}' "$3/gate.tsv"; }

# --------------------------------------------------------------- casos sintéticos
mk_suite sint_falha falha
mk_reg sint_falha suite sint_falha Makefile 1 - 30 "bash $T/suites/sint_falha.sh"
gate_run "$T/c01"
t01() { [ "$GATE_RC" -ne 0 ] && [ "$(row sint_falha "$T/c01")" = FAIL ]; }
ck 1 "F-portao: suite que falha ⇒ estado FAIL e exit do portao != 0" t01

mk_suite sint_bloq bloqueada
mk_reg sint_bloq suite sint_bloq Makefile 1 - 30 "bash $T/suites/sint_bloq.sh"
gate_run "$T/c02"
t02() { [ "$GATE_RC" -eq 0 ] && [ "$(row sint_bloq "$T/c02")" = BLOCKED ]; }
ck 2 "blocked=1 ⇒ BLOCKED (nunca PASS) e nao derruba o portao" t02

mk_reg sint_inexistente suite sint_inexistente tests/nao_existe_mesmo.sh 1 - 30 "bash tests/nao_existe_mesmo.sh"
gate_run "$T/c03"
t03() { [ "$(row sint_inexistente "$T/c03")" = NOT_IMPLEMENTED ] && [ "$GATE_RC" -eq 0 ]; }
ck 3 "etapa prevista sem arquivo ⇒ NOT_IMPLEMENTED, nao PASS" t03

mk_suite sint_verde verde
mk_reg sint_verde suite sint_verde Makefile 1 - 30 "bash $T/suites/sint_verde.sh"
GATE_SKIP=sint_verde gate_run "$T/c04"
t04() { [ "$(row sint_verde "$T/c04")" = SKIPPED ]; }
ck 4 "GATE_SKIP ⇒ SKIPPED (dispensa explicita, nao silencio)" t04

mk_reg sint_sem_ferr suite sint_sem_ferr Makefile 1 ferramenta_que_nao_existe 30 "bash $T/suites/sint_verde.sh"
gate_run "$T/c05"
t05() { [ "$(row sint_sem_ferr "$T/c05")" = BLOCKED ] && [ "$GATE_RC" -eq 0 ]; }
ck 5 "ferramenta ausente ⇒ BLOCKED (indisponibilidade ambiental != falha real)" t05

mk_suite sint_lento lento
mk_reg sint_lento suite sint_lento Makefile 1 - 2 "bash $T/suites/sint_lento.sh"
ANTES=$(ps -eo cmd | grep -c "sleep 45" || true)
gate_run "$T/c06"
sleep 1
DEPOIS=$(ps -eo cmd | grep -c "sleep 45" || true)
t06() { [ "$(row sint_lento "$T/c06")" = FAIL ] &&
        [ "$(campo sint_lento motivo "$T/c06")" = timeout ] &&
        [ "$DEPOIS" -le "$ANTES" ]; }
ck 6 "timeout ⇒ FAIL(motivo=timeout) e nenhum processo orphan do grupo" t06

mk_suite sint_calada falha_calada
mk_reg sint_calada suite sint_calada Makefile 1 - 30 "bash $T/suites/sint_calada.sh"
gate_run "$T/c07b"
t07b() { [ "$(row sint_calada "$T/c07b")" = FAIL ] && [ "$GATE_RC" -ne 0 ] &&
         [ "$(campo sint_calada motivo "$T/c07b")" = "exit=3" ]; }
ck 7 "suite que morre no fim (exit 3) com resumo limpo ⇒ FAIL(motivo=exit=3)" t07b

mk_suite sint_mudo mudo
mk_reg sint_mudo suite sint_mudo Makefile 1 - 30 "bash $T/suites/sint_mudo.sh"
gate_run "$T/c07"
t07() { [ "$(row sint_mudo "$T/c07")" = FAIL ] &&
        [ "$(campo sint_mudo motivo "$T/c07")" != ok ]; }
ck 7 "suite que sai 0 sem imprimir resumo ⇒ FAIL (resumo ausente nao e verde)" t07

# interrupcao: o portao tem de sair 130 e nao deixar o filho vivo
mk_suite sint_lento2 lento
mk_reg sint_lento2 suite sint_lento2 Makefile 1 - 300 "bash $T/suites/sint_lento2.sh"
mkdir -p "$T/c08"
env GATE_SUITES="$T/reg.tsv" GATE_OUT="$T/c08" GATE_ROOT="$V2" bash "$GATE" \
  > "$T/c08/stdout" 2>&1 &
GPID=$!
sleep 2
kill -TERM "$GPID" 2>/dev/null
wait "$GPID"; RC_INT=$?
sleep 1
t08() { [ "$RC_INT" = 130 ]; }
ck 8 "SIGTERM no portao ⇒ exit 130 (interrupcao e visivel, nao vira 0)" t08

# cwd inesperado e caminho com espaco
mkdir -p "$T/com espaco/saida"
mk_reg sint_cwd suite sint_verde Makefile 1 - 30 "bash $T/suites/sint_verde.sh"
( cd / && GATE_SUITES="$T/reg.tsv" GATE_OUT="$T/com espaco/saida" GATE_ROOT="$V2" \
    bash "$GATE" > "$T/com espaco/stdout" 2>&1 ); RC_CWD=$?
t09() { [ "$RC_CWD" -eq 0 ] && [ -s "$T/com espaco/saida/gate.tsv" ] &&
        grep -q "PASS=1" "$T/com espaco/stdout"; }
ck 9 "roda de cwd=/ e com espaco no caminho de saida, mesmo resultado" t09

# relatorio pre-existente tem de ser substituido, nunca acrescentado
mkdir -p "$T/c10"; printf 'LIXO\tDE\tEXECUCAO\tANTIGA\n' > "$T/c10/gate.tsv"
gate_run "$T/c10"
t10() { ! grep -q LIXO "$T/c10/gate.tsv" &&
        [ "$(head -1 "$T/c10/gate.tsv")" = "$(printf 'etapa\testado\tobrig\tassercoes\tfalhas\tblocked\texit\tms\tmotivo\tcomando')" ]; }
ck 10 "relatorio pre-existente e sobrescrito (sem anexar execucao anterior)" t10

# repetibilidade: duas corridas produzem o mesmo TSV, exceto a coluna de duracao
gate_run "$T/c11a"; gate_run "$T/c11b"
t11() { diff <(cut -f1-7,9,10 "$T/c11a/gate.tsv") <(cut -f1-7,9,10 "$T/c11b/gate.tsv") >/dev/null; }
ck 11 "execucao repetida e comparavel (TSV identico salvo a duracao)" t11

# --------------------------------------------------------------- portao real
mkdir -p "$T/real"; env -u GATE_SUITES GATE_OUT="$T/real" bash "$GATE" > "$T/real/stdout" 2>&1; REAL_RC=$?
# O portao real e cobrado por INVARIANTES, nao por totais exatos: prender "194 assercoes" fazia o
# caso falhar toda vez que uma suite nova entrava (aconteceu na R-6). O que nao pode mudar e:
# nenhuma FAIL, nenhum estado desconhecido, e o piso de cobertura da R-8 nunca regredir.
t12() { [ "$REAL_RC" -eq 0 ] &&
        [ "$(awk -F'\t' 'NR>1 && $2=="FAIL"' "$T/real/gate.tsv" | wc -l)" = 0 ] &&
        [ "$(awk -F'\t' 'NR>1 && $2!~/^(PASS|FAIL|BLOCKED|NOT_IMPLEMENTED|SKIPPED)$/' \
             "$T/real/gate.tsv" | wc -l)" = 0 ] &&
        [ "$(awk -F'\t' 'NR>1 && $2=="PASS"' "$T/real/gate.tsv" | wc -l)" -ge 9 ] &&
        [ "$(awk -F'\t' 'NR>1{s+=$4} END{print s+0}' "$T/real/gate.tsv")" -ge 194 ]; }
ck 12 "portao real: exit 0, zero FAIL, estados conhecidos, >=9 PASS e >=194 assercoes (piso R-8)" t12

# referencia ausente: pe/data viram BLOCKED, os selftests continuam PASS, portao nao falha
mkdir -p "$T/semref"; env -u GATE_SUITES GATE_OUT="$T/semref" MU_REF_DATA="$T/nao-existe" \
  bash "$GATE" > "$T/semref/stdout" 2>&1; SEMREF_RC=$?
t13() { [ "$SEMREF_RC" -eq 0 ] &&
        [ "$(row pe "$T/semref")" = BLOCKED ] && [ "$(row data "$T/semref")" = BLOCKED ] &&
        [ "$(row pe-selftest "$T/semref")" = PASS ] && [ "$(row data-selftest "$T/semref")" = PASS ]; }
ck 13 "MU_REF_DATA inexistente ⇒ pe/data BLOCKED, selftests PASS, portao exit 0" t13

# --------------------------------------------------------------- F12 / F13 / F14
# F12 — o portao ignora o exit code da suite?  (diferencial: copia mutada vs portao real)
sed 's/wait "$pid" || STEP_EXIT=$?/wait "$pid" 2>\/dev\/null; STEP_EXIT=0  # F12/' \
  "$GATE" > "$T/mut12.sh"
mk_suite f12_falha falha_calada
printf 'f12_falha\tsuite\tf12_falha\tMakefile\t1\t-\t30\tbash %s/suites/f12_falha.sh\n' "$T" \
  > "$T/reg_f12.tsv"
mkdir -p "$T/f12" "$T/f12real"
GATE_SUITES="$T/reg_f12.tsv" GATE_OUT="$T/f12" GATE_ROOT="$V2" bash "$T/mut12.sh" \
  > "$T/f12/stdout" 2>&1; RC_M12=$?
GATE_SUITES="$T/reg_f12.tsv" GATE_OUT="$T/f12real" GATE_ROOT="$V2" bash "$GATE" \
  > "$T/f12real/stdout" 2>&1; RC_R12=$?
t14() { grep -q 'STEP_EXIT=0  # F12' "$T/mut12.sh" &&   # a mutacao realmente entrou na copia
        [ "$RC_M12" -eq 0 ] && [ "$RC_R12" -ne 0 ]; }   # mutada nao detecta; a real detecta
ck 14 "F12: ignorar o exit code da suite quebra a deteccao (real exit!=0, mutada exit=0)" t14

# F13 — blocked vira PASS?
sed 's/ST_STATE=BLOCKED; ST_REASON="blocked=\$ST_BLOCK"/ST_STATE=PASS; ST_REASON="F13"/' \
  "$GATE" > "$T/mut13.sh"
mk_suite f13_bloq bloqueada
printf 'f13_bloq\tsuite\tf13_bloq\tMakefile\t1\t-\t30\tbash %s/suites/f13_bloq.sh\n' "$T" \
  > "$T/reg_f13.tsv"
mkdir -p "$T/f13" "$T/f13real"
GATE_SUITES="$T/reg_f13.tsv" GATE_OUT="$T/f13" GATE_ROOT="$V2" bash "$T/mut13.sh" \
  > "$T/f13/stdout" 2>&1
GATE_SUITES="$T/reg_f13.tsv" GATE_OUT="$T/f13real" GATE_ROOT="$V2" bash "$GATE" \
  > "$T/f13real/stdout" 2>&1
t15() { grep -q 'ST_REASON="F13"' "$T/mut13.sh" &&
        [ "$(row f13_bloq "$T/f13")" = PASS ] &&
        [ "$(row f13_bloq "$T/f13real")" = BLOCKED ]; }
ck 15 "F13: tratar blocked como PASS e detectavel (mutada=PASS, real=BLOCKED)" t15

# F14 — suite REAL forçada a falhar (mutacao no arquivo, com restauracao conferida por sha256)
cp "$V2/tests/make_parse.sh" "$T/make_parse.orig"
SHA_ANTES=$(sha256sum "$T/make_parse.orig" | cut -c1-16)
printf '\nexit 1  # FALSIFICACAO F14\n' >> "$V2/tests/make_parse.sh"
mkdir -p "$T/f14"; env -u GATE_SUITES GATE_OUT="$T/f14" bash "$GATE" > "$T/f14/stdout" 2>&1; RC_F14=$?
cp "$T/make_parse.orig" "$V2/tests/make_parse.sh"
SHA_DEPOIS=$(sha256sum "$V2/tests/make_parse.sh" | cut -c1-16)
t16() { [ "$RC_F14" -ne 0 ] && [ "$(row make-sintaxe "$T/f14")" = FAIL ] &&
        [ "$SHA_ANTES" = "$SHA_DEPOIS" ]; }
ck 16 "F14: suite real forçada a falhar ⇒ portao exit!=0; restauracao confere por sha256" t16

mkdir -p "$T/pos"; env -u GATE_SUITES GATE_OUT="$T/pos" GATE_ONLY=make-sintaxe bash "$GATE" > "$T/pos/stdout" 2>&1
RC_POS=$?
t17() { [ "$RC_POS" -eq 0 ] && [ "$(row make-sintaxe "$T/pos")" = PASS ]; }
ck 17 "apos a reversao da F14 a etapa volta a PASS" t17

# caso 19: etapa duplicada no registro (defeito real que aconteceu: `conform` foi criada sem
# remover o placeholder NOT_IMPLEMENTED e as assercoes foram contadas em dobro)
printf 'dup\tsuite\tdup\tMakefile\t1\t-\t30\ttrue\ndup\tsuite\tdup\tMakefile\t1\t-\t30\ttrue\n' \
  > "$T/reg_dup.tsv"
mkdir -p "$T/c19"
env GATE_SUITES="$T/reg_dup.tsv" GATE_OUT="$T/c19" GATE_ROOT="$V2" bash "$GATE" \
  > "$T/c19/stdout" 2>&1; RC_DUP=$?
t19() { [ "$RC_DUP" -eq 2 ] && grep -qi 'duplicad' "$T/c19/stdout"; }
ck 19 "etapa duplicada no registro ⇒ portao sai 2 com erro (nao conta assercao em dobro)" t19

printf '1..%d\n# gate_state=%d falhas=%d blocked=0\n' "$n" "$n" "$bad"
[ "$bad" -eq 0 ] || exit 1
