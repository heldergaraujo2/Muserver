#!/usr/bin/env bash
# run_all.sh — portão único de qualidade do v2 (fase R-8).
#
# CONTRATO DE EXECUÇÃO (o que este script garante, e o que ele recusa garantir)
#
# Estados, e por que eles não são sinônimos:
#   PASS             exit 0, falhas=0, blocked=0, e linha de resumo presente e com o nome da etapa
#   FAIL             exit != 0, ou falhas>0, ou resumo ausente, ou timeout
#   BLOCKED          dependência externa concreta ausente (referência, ferramenta) — não é aprovação
#   NOT_IMPLEMENTED  etapa prevista no plano cujo arquivo ainda não existe — não é aprovação
#   SKIPPED          dispensada por decisão explícita desta execução (GATE_ONLY/GATE_SKIP/opt-in)
#
# Regras herdadas e mantidas de propósito:
#   - sem `set -e`: cada etapa decide por si, e uma falha não pode abortar o diagnóstico;
#   - `blocked != aprovado`: BLOCKED e NOT_IMPLEMENTED nunca viram PASS e são contados à parte;
#   - resumo ausente é FAIL, não PASS: suíte que não imprime nada não passou, ela não disse nada;
#   - cada etapa roda em grupo de processo próprio (`setsid`) e é morta por PID/grupo, nunca por
#     `pkill -f` (padrão que já matou o próprio shell em rodada anterior);
#   - nada aqui escreve em `MuServer/` nem executa binário do pacote original;
#   - a saída não depende de estado residual: `out/gate/` é recriado a cada execução.
#
# Ambiente:
#   MU_REF_DATA     referência original (padrão: ../MuServer). Ausente ⇒ pe/data viram BLOCKED.
#   GATE_ONLY       lista de etapas a executar (as demais ficam SKIPPED)
#   GATE_SKIP       lista de etapas a dispensar
#   GATE_FULL=1     inclui as etapas opt-in caras (net-matrix, persistência)
#   GATE_ROOT       raiz do projeto (padrão: derivada do caminho do script)
#   GATE_OUT        diretório de saída (padrão: out) — usado pelo gate_state.sh
#   GATE_REPORT     caminho do TSV (padrão: $GATE_OUT/gate.tsv)
#   GATE_SUITES     arquivo de registro alternativo (usado pelo tests/gate_state.sh)
#
# Saída: mesa legível no stdout + TSV em $GATE_REPORT + log por etapa em out/gate/<etapa>.log
# Exit: 0 sem FAIL; 1 com qualquer FAIL; 130 se interrompido.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# raiz resolvida a partir do script (não do cwd). GATE_ROOT existe para o gate_state.sh poder
# executar uma copia mutada do portao, que mora em diretorio temporario, contra a arvore real.
ROOT=${GATE_ROOT:-$(cd "$HERE/.." && pwd)}
cd "$ROOT" || exit 2
OUT=${GATE_OUT:-$ROOT/out}   # GATE_OUT permite ao gate_state.sh rodar o portao em diretorio proprio
GATE_DIR=$OUT/gate
REPORT=${GATE_REPORT:-$OUT/gate.tsv}
LOGDIR=$GATE_DIR
export MU_REF_DATA=${MU_REF_DATA:-$ROOT/../MuServer}

rm -rf "$GATE_DIR"                                 # nenhuma dependência de execução anterior
mkdir -p "$LOGDIR"

# ---------------------------------------------------------------- registro de etapas
# nome | arquivo_exigido | obrigatoria(1/0) | ferramenta | timeout_s | comando
# arquivo_exigido ausente ⇒ NOT_IMPLEMENTED (sem executar nada).
# nome | tipo | rotulo_do_resumo | arquivo_exigido | obrigatoria | ferramenta | timeout_s | comando
#   tipo=suite  exige a linha `# <rotulo>=<n> falhas=<f> [blocked=<b>]`; resumo ausente e FAIL
#   tipo=cmd    e pre-condicao (compilar, por exemplo): vale o exit code, nao ha assercao
DEFAULT_SUITES='build	cmd	build	out/wire.o	1	cc	600	make -s build
unit	suite	unit	tests/unit.c	1	cc	180	make -s unit
make-sintaxe	suite	make-sintaxe	Makefile	1	make	120	make -s make-sintaxe
net	suite	net	tests/net.sh	1	cc	420	make -s net
pe	suite	pe	tools/pe_probe.py	1	python3	300	make -s pe
data	suite	data	tools/data_probe.py	1	python3	300	make -s data
pe-selftest	suite	pe	tests/pe.sh	1	python3	120	make -s pe-selftest
data-selftest	suite	data	tests/data.sh	1	python3	120	make -s data-selftest
ref-intacta	suite	ref-intacta	tests/ref_check.sh	1	git	120	bash tests/ref_check.sh
net-matrix	suite	net	tests/net.sh	0	cc	1800	make -s net-matrix
persistencia	cmd	-	scripts/verify-backup.sh	0	git	600	bash scripts/verify-backup.sh
golden	suite	golden	tests/golden.sh	1	-	120	bash tests/golden.sh
interop	suite	interop	tests/interop.sh	1	-	120	bash tests/interop.sh
conform	suite	conform	tests/conform.sh	1	-	120	bash tests/conform.sh
fuzz	suite	fuzz	tests/fuzz.sh	1	-	300	bash tests/fuzz.sh
bench	cmd	-	bench/bench.c	0	cc	600	make -s bench'

SUITES=$DEFAULT_SUITES
if [ -n "${GATE_SUITES:-}" ]; then
  [ -r "$GATE_SUITES" ] || { printf 'run_all: GATE_SUITES ilegivel: %s\n' "$GATE_SUITES" >&2; exit 2; }
  SUITES=$(cat "$GATE_SUITES")
fi

# etapas caras: só com GATE_FULL=1 (fora disso são SKIPPED por decisão, não silêncio)
OPTIN="net-matrix persistencia"

in_list() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }

# ---------------------------------------------------------------- execução isolada
# Cada etapa roda como job de fundo com controle de trabalho ligado (`set -m`): o bash coloca o
# job num grupo de processo proprio, cujo lider e o PID que guardamos. O prazo vem do `timeout(1)`
# (nao de um watchdog de fundo: a versao anterior usava `sleep &` e o processo sobrevivia a etapa,
# acordava no meio de outra e ainda bloqueava o `wait` — medido em out/gate/build.timeout).
set -m
CUR_PID=""
sweep_group() {                       # varre o grupo inteiro: servidor de teste nao pode ficar orphan
  local pid=$1
  [ -n "$pid" ] || return 0
  kill -TERM "-$pid" 2>/dev/null
  sleep 1
  kill -KILL "-$pid" 2>/dev/null
  return 0
}
cleanup_and_die() {
  printf '\nrun_all: interrompido por %s\n' "$1" >&2
  sweep_group "$CUR_PID"
  exit 130
}
trap 'cleanup_and_die SIGINT' INT
trap 'cleanup_and_die SIGTERM' TERM
trap 'cleanup_and_die SIGHUP' HUP

STEP_EXIT=0; STEP_MS=0; STEP_TIMEDOUT=0
run_step() {
  local name=$1 tmo=$2 cmd=$3
  local log=$LOGDIR/$name.log t0 t1 pid
  t0=$(date +%s%3N)
  timeout --signal=TERM --kill-after=3s "$tmo" bash -c "cd '$ROOT' && $cmd" > "$log" 2>&1 &
  pid=$!
  CUR_PID=$pid
  STEP_EXIT=0
  wait "$pid" || STEP_EXIT=$?
  CUR_PID=""
  t1=$(date +%s%3N)
  STEP_MS=$((t1 - t0))
  STEP_TIMEDOUT=0
  if [ "$STEP_EXIT" = 124 ] || [ "$STEP_EXIT" = 137 ]; then
    STEP_TIMEDOUT=1
    sweep_group "$pid"          # o prazo estourou: garantir que nada do grupo ficou vivo
  fi
}

# ---------------------------------------------------------------- classificação
# classify <etapa> <exit> <ms> <timedout> <log> <obrig>
# preenche: ST_STATE ST_N ST_FAIL ST_BLOCK ST_REASON
ST_STATE=""; ST_N=0; ST_FAIL=0; ST_BLOCK=0; ST_REASON=""
classify() {
  local rotulo=$1 tipo=$2 st=$3 ms=$4 tmo=$5 log=$6
  local resumo
  ST_N=0; ST_FAIL=0; ST_BLOCK=0; ST_REASON=""
  if [ "$tmo" = 1 ]; then
    ST_STATE=FAIL; ST_REASON="timeout"; ST_FAIL=1; return
  fi
  if [ "$tipo" = cmd ]; then          # pre-condicao: nao produz assercao, so exit code
    if [ "$st" -eq 0 ]; then ST_STATE=PASS; ST_REASON="ok(cmd)"; else
      ST_STATE=FAIL; ST_REASON="exit=$st"; ST_FAIL=1; fi
    return
  fi
  resumo=$(awk -v nome="$rotulo" '
      $0 ~ "^# "nome"=[0-9]+ falhas=" { linha=$0 }
      END { if (linha != "") print linha }' "$log" 2>/dev/null)
  if [ -z "$resumo" ]; then
    # resumo ausente: a etapa não disse nada mensurável — nunca pode contar como verde
    ST_STATE=FAIL; ST_REASON="resumo_ausente(exit=$st)"; ST_FAIL=1; return
  fi
  ST_N=$(printf '%s\n' "$resumo" | sed -n "s/^# ${rotulo}=\([0-9]*\) .*/\1/p")
  ST_FAIL=$(printf '%s\n' "$resumo" | sed -n 's/.*falhas=\([0-9]*\).*/\1/p')
  ST_BLOCK=$(printf '%s\n' "$resumo" | sed -n 's/.*blocked=\([0-9]*\).*/\1/p')
  [ -n "$ST_N" ]    || ST_N=0
  [ -n "$ST_FAIL" ] || ST_FAIL=0
  [ -n "$ST_BLOCK" ]|| ST_BLOCK=0
  if [ "$st" -ne 0 ]; then
    ST_STATE=FAIL; ST_REASON="exit=$st"; return
  fi
  if [ "$ST_FAIL" -gt 0 ]; then
    ST_STATE=FAIL; ST_REASON="falhas=$ST_FAIL"; return
  fi
  if [ "$ST_BLOCK" -gt 0 ]; then
    ST_STATE=BLOCKED; ST_REASON="blocked=$ST_BLOCK"; return
  fi
  ST_STATE=PASS; ST_REASON="ok"
}

# ---------------------------------------------------------------- laço principal
TMP=$LOGDIR/.rows; : > "$TMP"
n_pass=0; n_fail=0; n_block=0; n_ni=0; n_skip=0; n_assert=0; n_failassert=0
t_ini=$(date +%s%3N)

while IFS=$'\t' read -r nome tipo rotulo arquivo obrig ferr tmo cmd; do
  [ -n "$nome" ] || continue
  case "$nome" in \#*) continue;; esac
  estado=""; motivo=""; st="-"; ms=0; a=0; f=0; b=0

  if [ -n "${GATE_ONLY:-}" ] && ! in_list "$GATE_ONLY" "$nome"; then
    estado=SKIPPED; motivo="fora_de_GATE_ONLY"
  elif [ -n "${GATE_SKIP:-}" ] && in_list "$GATE_SKIP" "$nome"; then
    estado=SKIPPED; motivo="GATE_SKIP"
  elif [ "$obrig" = 0 ] && [ -z "${GATE_FULL:-}" ] && in_list "$OPTIN" "$nome"; then
    estado=SKIPPED; motivo="opt-in(GATE_FULL=1)"
  elif [ -n "$arquivo" ] && [ ! -e "$ROOT/$arquivo" ]; then
    estado=NOT_IMPLEMENTED; motivo="ausente:$arquivo"
  elif [ "$ferr" != "-" ] && ! command -v "$ferr" >/dev/null 2>&1; then
    estado=BLOCKED; motivo="ferramenta_ausente:$ferr"
  else
    run_step "$nome" "$tmo" "$cmd"
    st=$STEP_EXIT; ms=$STEP_MS
    classify "$rotulo" "$tipo" "$st" "$ms" "$STEP_TIMEDOUT" "$LOGDIR/$nome.log"
    estado=$ST_STATE; motivo=$ST_REASON; a=$ST_N; f=$ST_FAIL; b=$ST_BLOCK
  fi

  case "$estado" in
    PASS) n_pass=$((n_pass+1)); n_assert=$((n_assert+a));;
    FAIL) n_fail=$((n_fail+1)); n_assert=$((n_assert+a)); n_failassert=$((n_failassert+f));;
    BLOCKED) n_block=$((n_block+1));;
    NOT_IMPLEMENTED) n_ni=$((n_ni+1));;
    SKIPPED) n_skip=$((n_skip+1));;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$nome" "$estado" "$obrig" "$a" "$f" "$b" "$st" "$ms" "$motivo" "$cmd" >> "$TMP"
done <<< "$SUITES"

t_fim=$(date +%s%3N)
total_ms=$((t_fim - t_ini))

# ---------------------------------------------------------------- relatórios
# caminhos relativos à raiz: o relatório não vaza o host nem precisa de edição para ser publicado
# caminhos relativos: o relatorio nao deve vazar o host. Se a saida esta fora da raiz (caso de
# GATE_OUT em diretorio temporario), tenta relativizar ao cwd; so entao aceita o absoluto.
rel() {
  case "$1" in
    "$ROOT"/*) printf '%s\n' "${1#$ROOT/}" ;;
    *) if command -v realpath >/dev/null 2>&1; then
         realpath -m --relative-to="$PWD" "$1" 2>/dev/null || printf '%s\n' "$1"
       else printf '%s\n' "$1"; fi ;;
  esac
}
printf 'etapa\testado\tobrig\tassercoes\tfalhas\tblocked\texit\tms\tmotivo\tcomando\n' > "$REPORT"
cat "$TMP" >> "$REPORT"

printf '\n=== PORTAO v2 (run_all.sh) ===\n'
printf '%-14s %-16s %5s %6s %5s %7s %5s %8s  %s\n' \
  etapa estado obr asser falha blocked exit ms motivo
while IFS=$'\t' read -r nome estado obrig a f b st ms motivo cmd; do
  printf '%-14s %-16s %5s %6s %5s %7s %5s %8s  %s\n' \
    "$nome" "$estado" "$obrig" "$a" "$f" "$b" "$st" "$ms" "$motivo"
done < "$TMP"

printf '\n'
printf 'PASS=%d  FAIL=%d  BLOCKED=%d  NOT_IMPLEMENTED=%d  SKIPPED=%d\n' \
  "$n_pass" "$n_fail" "$n_block" "$n_ni" "$n_skip"
printf 'assercoes=%d  falhas_de_assercao=%d  duracao_ms=%d  etapas=%d\n' \
  "$n_assert" "$n_failassert" "$total_ms" "$(wc -l < "$TMP")"
printf 'referencia=%s\n' "$( [ -d "$MU_REF_DATA" ] && echo presente || echo ausente )"
printf 'relatorio=%s  logs=%s/\n' "$(rel "$REPORT")" "$(rel "$LOGDIR")"
# o que foi efetivamente testado, e o que não foi — sem eufemismo
printf 'testado_de_fato=%s\n' \
  "$(awk -F'\t' '$2=="PASS"{printf "%s%s",sep,$1; sep=","}' "$TMP")"
printf 'nao_testado=%s\n' \
  "$(awk -F'\t' '$2!="PASS"{printf "%s%s(%s)",sep,$1,$2; sep=","}' "$TMP")"

[ "$n_fail" -eq 0 ] || exit 1
exit 0
